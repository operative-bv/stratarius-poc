-- ================================================================
-- T-042: cascade_stap3_structurele_vermindering pure functie
-- ================================================================
--
-- Formule met EXPLICIETE haakjes (fold uit T-026 plan-review operator precedence):
--   R = (F + α × GREATEST(0, S0-S) + δ × GREATEST(0, S-S1)) × μ
--
-- Principe IV KRITIEK: μ (niet fte_breuk) drijft R pro rata. Function accepteert
-- p_mu als parameter; leest GEEN dim_contract.fte_breuk. Caller (T-029 orchestrator)
-- passeert μ uit T-024 cascade_stap voor het contract-periode.
--
-- Data-driven filters (Principe II): F, α, δ, S0, S1 uit param_structurele_vermindering
-- via (werkgeverscategorie, periode) temporele join. GEEN hardcoded 0.14 / 375 / etc.
--
-- NULL contract (consistent met T-023/24/26/41): temporele miss → NULL.
-- Cascade orchestrator (T-029) detecteert en throwt gestructureerde fout.
--
-- Depends: T-042 HOTFIX (S0/S1 kolommen) + T-016 schema.
--
-- Rollback: DROP FUNCTION public.cascade_stap3_structurele_vermindering(numeric, numeric, smallint, date);


create or replace function public.cascade_stap3_structurele_vermindering(
    p_rsz_grondslag       numeric(18, 4),
    p_mu                  numeric(6, 4),
    p_werkgeverscategorie smallint,
    p_periode             date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    select (
        (
            pv.forfait
            -- laag-lonencomponent: alpha × max(0, S0 - S) (positief als S < S0)
          + pv.coefficient_a * greatest(0::numeric(18, 4), pv.drempel_s0 - p_rsz_grondslag)
            -- hoog-lonencomponent: delta × max(0, S - S1) (positief als S > S1)
          + pv.coefficient_b * greatest(0::numeric(18, 4), p_rsz_grondslag - pv.drempel_s1)
        )
        -- Principe IV: μ schaalt HELE R (expliciete buitenste haakjes voor operator precedence)
      * p_mu
    )::numeric(18, 4)
    from public.param_structurele_vermindering pv
    where pv.werkgeverscategorie  = p_werkgeverscategorie
      and p_periode              >= pv.geldig_van
      and (pv.geldig_tot is null or p_periode < pv.geldig_tot);
$$;

comment on function public.cascade_stap3_structurele_vermindering(numeric, numeric, smallint, date) is
    'Cascade stap 3: structurele RSZ-vermindering R = (F + alpha*GREATEST(0, S0-S) + delta*GREATEST(0, S-S1)) * mu. Principe II data-driven (F/alpha/delta/S0/S1 uit param_structurele_vermindering). Principe IV: mu drijft pro rata via expliciete buitenste haakjes (NIET fte_breuk). NULL contract: temporele miss -> NULL, cascade orchestrator T-029 detecteert. LANGUAGE SQL STABLE PARALLEL SAFE, search_path pinned.';

grant execute on function public.cascade_stap3_structurele_vermindering(numeric, numeric, smallint, date) to authenticated;
