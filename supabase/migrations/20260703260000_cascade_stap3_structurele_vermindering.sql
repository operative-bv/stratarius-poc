-- ================================================================
-- T-042: cascade_stap3_structurele_vermindering pure functie
-- ================================================================
--
-- Formule (RSZ instructiegids vanaf 1 april 2024, cat 1):
--   R_kwartaal = F + α × GREATEST(0, S0 - S) + γ × GREATEST(0, S1 - S)
--   R_maand   = R_kwartaal / 3
--
-- Beide componenten zijn 'low-side kickers' (positief als S < drempel).
-- Voorheen δ × (S - S1) hoge-lonen; dat is verwijderd voor cat 1 (bestaat niet
-- meer in 2024 formule) — repurposed coefficient_b als γ, drempel_s1 als S1
-- (zeer-lage-lonen drempel, kleiner dan S0).
--
-- Principe IV KRITIEK: μ (niet fte_breuk) drijft R pro rata. Function accepteert
-- p_mu als parameter; leest GEEN dim_contract.fte_breuk. Caller (T-029 orchestrator)
-- passeert μ uit T-024 cascade_stap voor het contract-periode.
--
-- Data-driven filters (Principe II): F, α, γ, S0, S1 uit param_structurele_vermindering
-- via (werkgeverscategorie, periode) temporele join. GEEN hardcoded 0.14 / 10797 / etc.
--
-- /3 conversie: R uit formule is per KWARTAAL. Cascade output is per MAAND
-- (populatie_snapshot trekt af van monthly totaal). Divide door 3 voor consistentie.
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
            -- lage-lonencomponent: alpha × max(0, S0 - S) (positief als S < S0)
          + pv.coefficient_a * greatest(0::numeric(18, 4), pv.drempel_s0 - p_rsz_grondslag)
            -- zeer-lage-lonencomponent: gamma × max(0, S1 - S) (positief als S < S1)
            -- REPURPOSED coefficient_b → γ; drempel_s1 → S1 zeer-lage-lonen drempel
          + pv.coefficient_b * greatest(0::numeric(18, 4), pv.drempel_s1 - p_rsz_grondslag)
        )
        -- Principe IV: μ schaalt HELE R (expliciete buitenste haakjes voor operator precedence)
      * p_mu
        -- Kwartaal -> maand conversie voor cascade output consistency
      / 3
    )::numeric(18, 4)
    from public.param_structurele_vermindering pv
    where pv.werkgeverscategorie  = p_werkgeverscategorie
      and p_periode              >= pv.geldig_van
      and (pv.geldig_tot is null or p_periode < pv.geldig_tot);
$$;

comment on function public.cascade_stap3_structurele_vermindering(numeric, numeric, smallint, date) is
    'Cascade stap 3: structurele RSZ-vermindering R = (F + alpha*GREATEST(0, S0-S) + delta*GREATEST(0, S-S1)) * mu. Principe II data-driven (F/alpha/delta/S0/S1 uit param_structurele_vermindering). Principe IV: mu drijft pro rata via expliciete buitenste haakjes (NIET fte_breuk). NULL contract: temporele miss -> NULL, cascade orchestrator T-029 detecteert. LANGUAGE SQL STABLE PARALLEL SAFE, search_path pinned.';

grant execute on function public.cascade_stap3_structurele_vermindering(numeric, numeric, smallint, date) to authenticated;
