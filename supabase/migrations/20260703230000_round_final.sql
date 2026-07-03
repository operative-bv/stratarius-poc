-- ================================================================
-- T-025: round_final centrale afrondingsfunctie + private helpers
-- ================================================================
--
-- Constitution Domain sectie (bindend): "Afronding gebeurt UITSLUITEND bij
-- eindpresentatie (rapport, factuur, export) via een expliciete afrondingsregel."
-- Deze migration levert die "expliciete regel" als één centrale function.
--
-- Semantiek per purpose:
--   display, report  → banker's rounding (round half to even)
--                       Rationale: DMFA-conform (KB 28/11/1969 art. 34); voorkomt
--                       systematische positieve bias over duizenden loonberekeningen.
--   export, invoice  → half-away-from-zero (Postgres default round())
--                       Rationale: commercial rounding voor CSV/factuur — culturele
--                       verwachting van klant (0.5 gaat altijd omhoog).
--   overig           → RAISE EXCEPTION SQLSTATE 22023 (invalid_parameter_value)
--                       Rationale (fold plan-review round 1, 3 lenses convergeerden):
--                       silent NULL zou onopgemerkt in loonstroken belanden. Fail-loud.
--
-- Principe I (effective-dating): N/A — stateless function.
-- Principe II (data-driven): purpose als parameter, geen hardcoded amount-branches.
-- Principe III (strict separation): DIT IS DE ENIGE afrondingsplek in Stratarius.
--   Cascade-tussenberekeningen behouden numeric(18,4); alle downstream cascade
--   functions (T-026+) roepen round_final aan bij eindpresentatie. Geen andere
--   round()/trunc()/.toFixed() mag op geldbedragen worden toegepast.
-- Principe IV (fte_breuk ≠ μ): N/A — function ziet geen breuken.
-- Principe V: TDD 2-commit — test-commit 73cd55b (42-round-final.sql plan(18))
--   is EERDER dan deze migration commit.
--
-- Design keuze — LANGUAGE plpgsql voor dispatcher (fold plan-review):
--   Aanvankelijk was dispatcher LANGUAGE SQL met `else null`. Plan-review lenses
--   (clean-code + security + error-handling) convergeerden op silent-failure risk.
--   plpgsql pure functie kan ook IMMUTABLE + PARALLEL SAFE zijn — geen optimizer-
--   verlies. RAISE EXCEPTION 22023 (invalid_parameter_value) is machine-readable.
--
-- Design keuze — unbounded p_bedrag numeric (fold plan-review):
--   Als p_bedrag numeric(18,4) was, zouden callers met >4-decimal precisie
--   impliciete PG-cast met round-half-away-from-zero ondergaan VOOR banker's kon
--   toegepast worden — kan spurious boundary detectie triggeren. Unbounded param
--   preserveert exacte caller-precisie.
--
-- Rollback (in omgekeerde afhankelijkheids-volgorde; T-026+ cascade functies
-- moeten EERST gedropt worden voor dependency-break):
--   DROP FUNCTION public.round_final(numeric, text);
--   DROP FUNCTION public._round_half_up_2(numeric);
--   DROP FUNCTION public._round_banker_2(numeric);


-- ================================================================
-- Private helper: _round_banker_2 (round half to even)
-- ================================================================

create or replace function public._round_banker_2(p_bedrag numeric)
    returns numeric(18, 2)
    language sql
    immutable
    parallel safe
as $$
    -- Algoritme (4 stappen):
    --   1. Schaal naar hele centen: scaled_cents = p_bedrag × 100
    --   2. Split in integer- en fractioneel deel:
    --        integer_cents = floor(scaled_cents)
    --        remainder     = scaled_cents - integer_cents
    --   3. Exact-half detectie: remainder = 0.5 → boundary geval
    --   4. Tie-break op pariteit: boundary + even integer → houd; boundary + oneven → +1.
    --      Geen boundary → normale Postgres round() (half-away-from-zero).
    --
    -- Negatief bereik: Postgres modulo houdt teken van dividend, dus
    --   (-413::bigint) % 2 = -1 (niet 0) → oneven-tak. Correct voor banker's:
    --   -4.135 → -413.5 → floor=-414, remainder=0.5, -414%2=0 (even) → -414/100 = -4.14. ✓
    with s as (
        select p_bedrag * 100 as scaled_cents
    ),
    f as (
        select
            scaled_cents,
            floor(scaled_cents)                as integer_cents,
            scaled_cents - floor(scaled_cents) as remainder
        from s
    )
    select case
        when f.remainder = 0.5 then
            case when (f.integer_cents::bigint) % 2 = 0
                 then (f.integer_cents / 100)::numeric(18, 2)         -- even: houd
                 else ((f.integer_cents + 1) / 100)::numeric(18, 2)   -- oneven: naar +1
            end
        else round(p_bedrag, 2)::numeric(18, 2)                       -- niet-boundary
    end
    from f;
$$;

comment on function public._round_banker_2(numeric) is
    'Private helper: banker''s rounding (round half to even) op 2 decimalen. Alleen aanroepbaar vanuit round_final dispatcher — GEEN GRANT aan authenticated. Handelt positief + negatief bereik symmetrisch af via floor + integer-cent pariteit. DMFA-conform per KB 28/11/1969 art. 34.';


-- ================================================================
-- Private helper: _round_half_up_2 (round half away from zero)
-- ================================================================

create or replace function public._round_half_up_2(p_bedrag numeric)
    returns numeric(18, 2)
    language sql
    immutable
    parallel safe
as $$
    -- Trivial wrapper op Postgres round() dat native half-away-from-zero doet.
    -- Bestaat voor symmetrie met _round_banker_2 — dispatcher heeft dan 2 helpers
    -- in plaats van 4 branches met 2 verschillende call-vormen. Toevoegen van een
    -- 5e purpose = 1 dispatcher-regel, geen wijziging aan methode-logica.
    select round(p_bedrag, 2)::numeric(18, 2);
$$;

comment on function public._round_half_up_2(numeric) is
    'Private helper: half-away-from-zero rounding (Postgres round() default) op 2 decimalen. Alleen aanroepbaar vanuit round_final dispatcher — GEEN GRANT aan authenticated. Voor export/invoice purposes (commercial rounding, niet DMFA).';


-- ================================================================
-- Public dispatcher: round_final
-- ================================================================

create or replace function public.round_final(
    p_bedrag  numeric,                     -- UNBOUNDED numeric — preserve caller precision
    p_purpose text default 'display'
)
    returns numeric(18, 2)
    language plpgsql
    immutable
    parallel safe
as $$
begin
    if p_purpose = 'display' or p_purpose = 'report' then
        return public._round_banker_2(p_bedrag);
    elsif p_purpose = 'export' or p_purpose = 'invoice' then
        return public._round_half_up_2(p_bedrag);
    else
        -- Note: plpgsql RAISE format spec is only '%' (not '%L' like format()). Wrap in single quotes
        -- expliciet voor auditbaar log-formaat consistent met pgTAP throws_ok verwachting.
        raise exception 'round_final: unknown purpose ''%''; allowed: display, report, export, invoice', p_purpose
            using errcode = '22023';  -- SQLSTATE 22023 = invalid_parameter_value
    end if;
end;
$$;

comment on function public.round_final(numeric, text) is
    'Centrale afrondingsfunctie (Principe III: DE ENIGE afrondingsplek). Purpose display/report → banker''s (DMFA-conform KB 28/11/1969 art. 34); export/invoice → half-away-from-zero (commercial). Unknown purpose raist SQLSTATE 22023 (invalid_parameter_value) — geen silent NULL. Unbounded p_bedrag numeric preserveert caller-precisie; cast naar (18,2) alleen op return. LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE — pure functie, geen zijeffecten.';


-- ================================================================
-- Privilege scoping (fold van security lens plan-review)
-- ================================================================

-- Helpers zijn intern — expliciet REVOKE zodat authenticated/anon ze NIET direct kan
-- aanroepen. Alleen public.round_final krijgt GRANT. Dit versterkt Principe III
-- (round_final is DE ENIGE afrondingsplek): als iemand banker''s wil, moet dat via
-- de dispatcher met bewuste purpose-keuze — audit-spoor in call-site.

revoke execute on function public._round_banker_2(numeric) from public;
revoke execute on function public._round_half_up_2(numeric) from public;

grant execute on function public.round_final(numeric, text) to authenticated;
