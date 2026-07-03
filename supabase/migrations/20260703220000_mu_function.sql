-- ================================================================
-- T-024: mu_van_prestatie pure functie (effectieve prestatiebreuk μ = Q/S)
-- ================================================================
--
-- Constitution Principe IV kritieke afdwinging:
--   μ IS NIET fte_breuk. dim_contract.fte_breuk (juridische tewerkstellingsbreuk,
--   statisch) en μ = Q/S (effectieve prestatiebreuk, dynamisch) zijn STRIKT gescheiden.
--   Deze function berekent μ uit fact_prestatie + param_arbeidsduur — leest NOOIT
--   dim_contract.fte_breuk.
--
-- Formule:
--   Q = SUM(fact_prestatie.uren) WHERE dim_prestatiecode.telt_voor_mu = true
--   S = param_arbeidsduur.gemiddelde_wekelijkse_uren × (52 / 12)
--       (referentie-uren per maand voor de PC van het contract)
--   μ = Q / S
--
-- telt_voor_mu filter is CRUCIAAL (Principe II data-driven):
--   'tijdelijke_urenvermindering' heeft telt_voor_mu=false in T-013 seed.
--   Die uren tellen NIET in Q — dat is precies wat μ < fte_breuk mogelijk maakt.
--
-- Principe I: temporele join op param_arbeidsduur.geldig_van/geldig_tot.
-- Principe III: pure functie, STABLE, PARALLEL SAFE. Geen tarieven in code.
-- Principe V: TDD 2-commit — test-commit d8d67f9 tijdstip EERDER dan deze migration.
--
-- HOTFIX ISS-034: T-022 definieerde fact_prestatie.uren als numeric(6,4) (max
-- 99.9999) — te krap voor realistische maandelijkse prestaties (164.67u voltijds
-- bediende, 173.33u voltijds bouw, 200u+ overuren). ALTER naar numeric(10,4)
-- inline hier want mu_van_prestatie tests vereisen realistische uren-waarden.


-- ================================================================
-- HOTFIX: fact_prestatie.uren numeric(6,4) → numeric(10,4)
-- ================================================================

alter table public.fact_prestatie
    alter column uren type numeric(10, 4);


-- ================================================================
-- FUNCTION: mu_van_prestatie
-- ================================================================



create or replace function public.mu_van_prestatie(
    p_contract_id uuid,
    p_periode date
)
    returns numeric(6, 4)
    language sql
    stable
    parallel safe
as $$
    with q as (
        select coalesce(sum(fp.uren)::numeric(18, 4), 0::numeric(18, 4)) as som_uren
        from public.fact_prestatie fp
        join public.dim_prestatiecode dp on dp.prestatiecode = fp.prestatiecode_id
        where fp.contract_id = p_contract_id
          and fp.periode = p_periode
          and dp.telt_voor_mu = true
    ),
    s as (
        -- Cast intermediate naar numeric(18,4) — S = wekelijkse_uren × 52/12 kan
        -- 100+ opleveren (bv. 40 × 4.333 = 173.33), wat numeric(6,4) niet aankan.
        select (a.gemiddelde_wekelijkse_uren::numeric(18, 4) * (52::numeric(18, 4) / 12::numeric(18, 4))) as ref_uren
        from public.dim_contract c
        join public.param_arbeidsduur a
          on a.pc_id = c.pc_id
         and p_periode >= a.geldig_van
         and (a.geldig_tot is null or p_periode < a.geldig_tot)
        where c.contract_id = p_contract_id
    )
    select (q.som_uren / nullif(s.ref_uren, 0::numeric(18, 4)))::numeric(6, 4)
    from q, s;
$$;

comment on function public.mu_van_prestatie(uuid, date) is
    'Pure functie: mu = Q/S waar Q = sum fact_prestatie.uren met dim_prestatiecode.telt_voor_mu=true, S = param_arbeidsduur.gemiddelde_wekelijkse_uren x (52/12) via temporele join. Principe IV: leest GEEN dim_contract.fte_breuk. Q=0 (coalesce) bij missing fact; NULL bij missing param_arbeidsduur (cross-join met lege set). Caller detecteert NULL en throwt gestructureerde fout.';

-- GRANT EXECUTE aan authenticated: function is read-only op params + facts (die
-- zelf role-scoped zijn via RLS). Geen SECURITY DEFINER nodig — STABLE volstaat.
grant execute on function public.mu_van_prestatie(uuid, date) to authenticated;
