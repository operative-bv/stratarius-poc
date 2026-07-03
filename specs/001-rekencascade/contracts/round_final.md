# Contract: `round_final`

**Status**: implemented (T-025 delivered) | **Owner ticket**: T-025

## Signature (as-implemented)

```sql
create or replace function public.round_final(
    p_bedrag  numeric,                       -- UNBOUNDED numeric — preserve caller precision
    p_purpose text default 'display'
) returns numeric(18, 2)
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
        raise exception 'round_final: unknown purpose ''%''; allowed: display, report, export, invoice', p_purpose
            using errcode = '22023';  -- SQLSTATE 22023 = invalid_parameter_value
    end if;
end;
$$;
```

Private helpers (REVOKE from public — alleen dispatcher heeft GRANT):

- `public._round_banker_2(numeric) → numeric(18,2)` — banker's (round half to even)
- `public._round_half_up_2(numeric) → numeric(18,2)` — half-away-from-zero

## Rationale voor design keuzes

- **LANGUAGE plpgsql** i.p.v. SQL: plan-review round 1 identificeerde silent-NULL risico op unknown purpose. plpgsql RAISE EXCEPTION met SQLSTATE 22023 (invalid_parameter_value) maakt typos loud. plpgsql pure functies kunnen ook IMMUTABLE + PARALLEL SAFE zijn — geen optimizer-verlies.
- **Unbounded `p_bedrag numeric`** (geen `(18,4)`): plan-review error-handling lens flagde dat caller met >4-decimalen precisie impliciete PG-cast met round-half-away-from-zero zou ondergaan VOOR banker's kan toegepast worden — kan spurious boundary detectie triggeren. Unbounded param preserveert exacte caller-precisie.
- **Aparte `_round_half_up_2` helper**: plan-review clean-code lens flagde dispatcher-duplicatie (banker × 2, half-up × 2 branches). Symmetric helpers maakt toevoegen van 5e purpose een 1-regel wijziging.
- **REVOKE helpers, GRANT dispatcher**: plan-review security lens flagde dat helpers met `_prefix` naming (intern) geen execute-recht mogen krijgen. Alleen `round_final` is publiek toegankelijk — call-site heeft altijd expliciete purpose-keuze (audit-spoor).

## Banker's rounding rationale (unchanged)

- **Systematische bias voorkomen**: standaard round-half-away-from-zero rondt 0.5 altijd naar boven af, wat over duizenden loonberekeningen een systematisch positieve bias oplevert (fiscaal ongewenst).
- **Banker's rounding** (round half to even): 0.5 rondt naar dichtstbijzijnde even; over grote reeksen middelt bias uit.
- **Belgische fiscale praktijk**: RSZ hanteert banker's rounding voor eindafronding op DMFA-aangiftes (bevestigd via KB 28 nov 1969, art. 34).

## Semantiek per purpose

| purpose | rounding methode | use case |
|---|---|---|
| `display` (default) | banker's | UI-weergave, dashboard-getallen |
| `report` | banker's | PDF-rapport, loonstrook, DMFA-aangifte |
| `export` | half-away-from-zero | CSV/Excel bulk-export naar externe systemen |
| `invoice` | half-away-from-zero | Factuur naar tenant (commercial rounding) |
| `overig` (typo) | `raise exception 22023` | Fail-loud, geen silent NULL |

## Constitution Principe III compliance

- **Centrale afronding**: dit is de ENIGE plek in de cascade waar afronding plaatsvindt. Alle intermediate berekeningen gebruiken `numeric(18,4)` cent-precisie.
- **Cascade-functies (T-026/T-027/T-028) roepen `round_final` aan** bij het schrijven naar `fact_loonkost.bedrag`. Geen enkele andere function/module mag `round()`, `trunc()`, `.toFixed()` gebruiken op geldbedragen.
- **CI-enforcement gedeferred naar ISS-035** (grep-based lint).

## Preconditions

- `p_bedrag` is unbounded `numeric` (kan positief, nul, negatief, of NULL zijn).
- `p_purpose` is één van `{'display', 'report', 'export', 'invoice'}` (case-sensitive, lowercase). Bij onbekende purpose: RAISE.

## Postconditions

- Return-waarde is `numeric(18,2)`: exact 2 decimalen precisie.
- Voor 0.5-boundary cases + banker's purposes: banker's regel toegepast.
- Voor 0.5-boundary cases + half-up purposes: half-away-from-zero (Postgres default round).
- `NULL bedrag` → `NULL` (documented explicit propagation — bedrag is optional, purpose is niet).
- `IMMUTABLE`: identieke input → identieke output altijd. Verified via `pg_proc.provolatile = 'i'`.
- `PARALLEL SAFE`.

## Foutmodes

- **Unknown purpose**: `RAISE EXCEPTION SQLSTATE 22023 (invalid_parameter_value)`. Message bevat de daadwerkelijke purpose-waarde voor audit-trail: `round_final: unknown purpose 'random_typo'; allowed: display, report, export, invoice`.
- **Overflow bij extreem grote bedragen**: Postgres numeric-limit is enorm; praktisch geen risico voor loonkost-berekeningen.

## Testbaarheid (Principe V) — pgTAP plan(18)

Zie `supabase/tests/database/42-round-final.sql` voor volledige test suite. Coverage:

- **T1-T2b**: function existence van dispatcher + beide helpers
- **T3-T4**: simpele niet-boundary cases (default purpose = display)
- **T5-T7**: banker's boundary positief (4.125→4.12 even, 4.135→4.14 oneven, 0.005→0.00 nul)
- **T8-T9**: banker's boundary negatief (-4.125→-4.12, -4.135→-4.14) — Postgres modulo sign semantics
- **T10-T12**: half-up boundary voor export/invoice (0.005→0.01 divergeert van banker's 0.00)
- **T13**: purpose divergentie bewijs (display(4.125) ≠ export(4.125))
- **T14**: unknown purpose raist SQLSTATE 22023 met exacte message
- **T14b**: NULL bedrag → NULL (documented explicit)
- **T14c**: unbounded param preservation (4.1250001 → 4.13, NIET 4.12 zoals bij (18,4)-cast)
- **T15a**: determinisme (2 opeenvolgende calls identiek)
- **T15b**: IMMUTABLE label verificatie via `pg_proc.provolatile = 'i'`

## Follow-ups

- **ISS-035**: CI grep-based lint dat verifieert `round_final` is de ENIGE call-site.
- **ISS-036**: TypeScript parallel implementatie voor Phase 7 UI-simulator (byte-voor-byte identieke boundary-uitkomst).
