-- ================================================================
-- T-026: cascade_stap1_rsz_grondslag pure functie (scope-reduced)
-- ================================================================
--
-- Constitution Principe III: pure SQL functie in de rekencascade. Berekent
-- RSZ-grondslag = som(rsz_plichtige componenten) + overloon.
--
-- Principe II data-driven filters:
--   som_rsz_plichtige   → dim_looncomponent.rsz_plichtig = true (bestaande gedragstag)
--   maandloon           → dim_looncomponent.is_basisloon = true (NIEUWE gedragstag, HOTFIX hier)
--   overloon prestaties → dim_prestatiecode.toeslag_pct IS NOT NULL (bestaande gedragstag)
--
-- Overloon-formule:
--   overloon = SUM(fact_prestatie.uren × uurloon × dim_prestatiecode.toeslag_pct)
--   uurloon = uurloon_van_maandloon(maandloon, contract.pc_id, periode) [T-023]
--   waar maandloon = SUM(fact_looncomponent.bedrag) WHERE is_basisloon = true
--
-- HOTFIX rationale:
--   Overloon-berekening vereist "wat is basisloon" om uurloon te bepalen.
--   Zonder een gedragstag zou de function moeten switchen op component_id = 'basisloon'
--   (Principe II inbreuk) OF som(rsz_plichtige) gebruiken als maandloon-proxy
--   (verkeerd: eindejaarspremie zit erin). Data-driven oplossing: is_basisloon
--   boolean gedragstag, seed alleen 'basisloon' component op true.
--   Filed ISS-039 voor volledig audit van seed (voor nieuwe basisloon-varianten
--   zoals basisloon_gedetacheerd zou is_basisloon=true nodig zijn).
--
-- Scope-reductie van origineel T-026 stap 1-3 (2026-07-03):
--   Plan-review round 1 vond 4 critical blockers. Stap 2 → T-041, stap 3 → T-042.
--
-- Principe V: TDD 2-commit — test-commit 3cb28bf (43-cascade-stap1-rsz-grondslag.sql
--   plan(12)) is EERDER dan deze migration commit.
--
-- Rollback (in omgekeerde afhankelijkheids-volgorde):
--   DROP FUNCTION public.cascade_stap1_rsz_grondslag(uuid, date, uuid);
--   ALTER TABLE public.dim_looncomponent DROP COLUMN is_basisloon;


-- ================================================================
-- HOTFIX: is_basisloon gedragstag op dim_looncomponent
-- ================================================================

alter table public.dim_looncomponent
    add column is_basisloon boolean not null default false;

update public.dim_looncomponent
    set is_basisloon = true
    where component_id = 'basisloon';

comment on column public.dim_looncomponent.is_basisloon is
    'Principe II gedragstag: is dit component het maandloon dat gebruikt wordt voor uurloon-berekening (bij overloon)? Alleen basisloon = true per default seed. Nieuwe basisloon-varianten (bv. basisloon_gedetacheerd) moeten expliciet is_basisloon=true krijgen. Cascade stap 1 gebruikt deze tag NIET om switching op identity te vervangen.';


-- ================================================================
-- FUNCTION: cascade_stap1_rsz_grondslag
-- ================================================================

create or replace function public.cascade_stap1_rsz_grondslag(
    p_contract_id  uuid,
    p_periode      date,
    p_scenario_id  uuid
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    with
    som_rsz_plichtige as (
        select coalesce(sum(fl.bedrag), 0::numeric(18, 4))::numeric(18, 4) as bedrag
        from public.fact_looncomponent fl
        join public.dim_looncomponent dl on dl.component_id = fl.component_id
        where fl.contract_id  = p_contract_id
          and fl.periode      = p_periode
          and fl.scenario_id  = p_scenario_id
          and dl.rsz_plichtig = true
    ),
    maandloon as (
        select coalesce(sum(fl.bedrag), 0::numeric(18, 4))::numeric(18, 4) as bedrag
        from public.fact_looncomponent fl
        join public.dim_looncomponent dl on dl.component_id = fl.component_id
        where fl.contract_id   = p_contract_id
          and fl.periode       = p_periode
          and fl.scenario_id   = p_scenario_id
          and dl.is_basisloon  = true
    ),
    contract_pc as (
        select c.pc_id
        from public.dim_contract c
        where c.contract_id = p_contract_id
    ),
    uurloon as (
        select public.uurloon_van_maandloon(
            m.bedrag,
            (select pc_id from contract_pc),
            p_periode
        ) as bedrag
        from maandloon m
    ),
    overloon as (
        -- Data-driven filter: toeslag_pct IS NOT NULL identificeert overuren-prestatiecodes.
        -- GEEN COALESCE hier: SUM levert NULL bij lege set OF bij NULL uurloon.
        -- had_rows onderscheidt de twee gevallen zodat NULL alleen bij "overuren aanwezig
        -- maar uurloon-berekening faalde" propageert — geen silent 0 dus.
        select
            sum(fp.uren::numeric(18, 4) * u.bedrag * dp.toeslag_pct::numeric(18, 4))::numeric(18, 4) as sum_bedrag,
            count(*) > 0 as had_rows
        from public.fact_prestatie fp
        join public.dim_prestatiecode dp on dp.prestatiecode = fp.prestatiecode_id
        cross join uurloon u
        where fp.contract_id   = p_contract_id
          and fp.periode       = p_periode
          and dp.toeslag_pct is not null
    )
    select case
        when o.had_rows and o.sum_bedrag is null
            then null::numeric(18, 4)  -- overuren aanwezig maar uurloon niet te berekenen → propageer NULL
        else (s.bedrag + coalesce(o.sum_bedrag, 0::numeric(18, 4)))::numeric(18, 4)
    end
    from som_rsz_plichtige s
    cross join overloon o;
$$;

comment on function public.cascade_stap1_rsz_grondslag(uuid, date, uuid) is
    'Cascade stap 1: RSZ-grondslag = som(fact_looncomponent WHERE rsz_plichtig) + overloon(overuren × uurloon × toeslag_pct). Principe II data-driven filters op rsz_plichtig, is_basisloon en toeslag_pct IS NOT NULL — GEEN switching op component_id/prestatiecode identity. Overloon-uurloon via uurloon_van_maandloon(T-023) met maandloon = som(WHERE is_basisloon=true). NULL contract: als overuren aanwezig EN param_arbeidsduur mist voor periode → SUM propageert NULL; caller detecteert. Geen overuren OF geen param_arbeidsduur zonder overuren → COALESCE(0). LANGUAGE SQL STABLE PARALLEL SAFE met pinned search_path=public,pg_temp. Scope-reduced van origineel T-026 stap 1-3 (2026-07-03 plan-review); stap 2→T-041, stap 3→T-042.';

grant execute on function public.cascade_stap1_rsz_grondslag(uuid, date, uuid) to authenticated;
