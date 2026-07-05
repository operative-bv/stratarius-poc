-- ================================================================
-- Fix drift op cascade_stap3 + cascade_stap6 function bodies
-- ================================================================
--
-- Diff met prod (na eerste repair migration 001350) toont dat twee
-- cascade functions verkeerde bodies hebben op prod door dezelfde
-- edit-in-place antipattern als 3d31780 (T-052):
--
--   cascade_stap3_structurele_vermindering:
--     Prod: pv.coefficient_b * greatest(0, p_rsz_grondslag - pv.drempel_s1)
--           (oude pre-april-2024 δ-term voor hoge lonen)
--           GEEN /3 kwartaal→maand conversie
--     Local: pv.coefficient_b * greatest(0, pv.drempel_s1 - p_rsz_grondslag)
--            (2024 γ-term voor zeer-lage lonen)
--            met /3 conversion
--     Symptoom: structurele vermindering op prod bijna 0 voor lage bruto's
--     (S > S1 dus greatest = 0), terwijl 2024 formule ~ €480/m geeft.
--
--   cascade_stap6_vakantiegeld:
--     Prod: (p_bruto * (enkel_pct + dubbel_pct))
--           JAARLIJKSE rate rechtstreeks toegepast → 100% van bruto per maand
--     Local: (p_bruto * (enkel_pct + dubbel_pct) / 12)
--           jaar→maand accrual conversie
--     Symptoom: vakantiegeld €2491,75 bij bruto €2500 (van 100% ipv 8%).
--
-- Rollback: run CREATE OR REPLACE met de oude prod-bodies (zie diff-log).
-- ================================================================

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
          + pv.coefficient_a * greatest(0::numeric(18, 4), pv.drempel_s0 - p_rsz_grondslag)
          + pv.coefficient_b * greatest(0::numeric(18, 4), pv.drempel_s1 - p_rsz_grondslag)
        )
      * p_mu
      / 3
    )::numeric(18, 4)
    from public.param_structurele_vermindering pv
    where pv.werkgeverscategorie  = p_werkgeverscategorie
      and p_periode              >= pv.geldig_van
      and (pv.geldig_tot is null or p_periode < pv.geldig_tot);
$$;

create or replace function public.cascade_stap6_vakantiegeld(
    p_bruto  numeric(18, 4),
    p_status text,
    p_periode date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    -- param_vakantiegeld bevat JAARLIJKSE rates (enkel + dubbel als deel van jaarloon).
    -- Cascade output is maandelijkse provisie → deel door 12.
    select (p_bruto * (pv.enkel_pct + pv.dubbel_pct) / 12)::numeric(18, 4)
    from public.param_vakantiegeld pv
    where pv.regime = p_status
      and p_periode >= pv.geldig_van
      and (pv.geldig_tot is null or p_periode < pv.geldig_tot);
$$;
