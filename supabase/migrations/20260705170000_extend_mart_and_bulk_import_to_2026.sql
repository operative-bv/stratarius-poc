-- ================================================================
-- Fase 5 (fiscale audit): mart_loonkloof + bulk_import naar 2026
-- ================================================================
--
-- mart_loonkloof heeft kwartaal_eindes hard-coded op 2024-03-31 t/m
-- 2024-12-31. Voor "we zijn up-to-date" pitch moeten we minimaal Q2
-- 2026 tonen. Rek uit tot 2024-Q1 t/m 2026-Q4 (12 kwartalen).
--
-- bulk_import_populatie heeft p_periode default '2024-06-01'. Verander
-- naar '2026-06-01' zodat "Laad demo dataset" default 2026 populatie
-- levert.
-- ================================================================

-- ================================================================
-- 1. mart_loonkloof met kwartaal-eindes tot 2026-12-31
-- ================================================================
drop materialized view if exists public.mart_loonkloof cascade;

create materialized view public.mart_loonkloof as
with
    kwartaal_eindes as (
        select generate_series('2024-03-31'::date, '2026-12-31'::date, interval '3 months')::date as referentiedatum
    ),
    contract_op_referentie as (
        select
            c.contract_id, c.persoon_id, c.pc_id, c.geldig_van, c.legale_entiteit_id,
            f.functieniveau,
            p.geslacht,
            k.referentiedatum
        from public.dim_contract c
        join public.dim_functie f on f.functie_id = c.functie_id
        join public.dim_persoon p on p.persoon_id = c.persoon_id
        cross join kwartaal_eindes k
        where c.geldig_van <= k.referentiedatum
          and (c.geldig_tot is null or c.geldig_tot > k.referentiedatum)
    ),
    lonen_maand as (
        select
            cr.persoon_id, cr.referentiedatum, cr.pc_id, cr.functieniveau, cr.geslacht,
            cr.geldig_van, cr.legale_entiteit_id,
            coalesce(sum(fl.bedrag) filter (where dl.is_basisloon), 0)::numeric(18, 4) as basis_vte,
            coalesce(sum(fl.bedrag) filter (where dl.rsz_plichtig and not dl.is_basisloon), 0)::numeric(18, 4) as variabele_vte
        from contract_op_referentie cr
        left join public.fact_looncomponent fl
            on fl.contract_id = cr.contract_id
            and fl.periode = date_trunc('month', cr.referentiedatum)::date
            and fl.scenario_id in (
                select s.scenario_id from public.dim_scenario s
                where s.kind = 'baseline'
                  and s.legale_entiteit_id = cr.legale_entiteit_id
            )
        left join public.dim_looncomponent dl on dl.component_id = fl.component_id
        group by cr.persoon_id, cr.referentiedatum, cr.pc_id, cr.functieniveau, cr.geslacht, cr.geldig_van, cr.legale_entiteit_id
    )
select
    lm.persoon_id,
    lm.legale_entiteit_id,
    lm.referentiedatum,
    extract(year from lm.referentiedatum)::text || '-Q' || extract(quarter from lm.referentiedatum)::text as kwartaal,
    public.uurloon_van_maandloon(lm.basis_vte, lm.pc_id, lm.referentiedatum) as uurloon_bruto,
    lm.basis_vte,
    lm.variabele_vte,
    lm.geslacht,
    lm.functieniveau,
    round(((lm.referentiedatum - lm.geldig_van)::numeric / 365.25), 2)::numeric(6, 2) as ancienniteit_jaren
from lonen_maand lm;

create unique index mart_loonkloof_pk on public.mart_loonkloof (persoon_id, referentiedatum);
create index mart_loonkloof_legale_entiteit_idx on public.mart_loonkloof (legale_entiteit_id);

comment on materialized view public.mart_loonkloof is
    'Loonkloof-mart per persoon × kwartaal. Kwartaal-eindes 2024-Q1 t/m 2026-Q4 (12 kwartalen). Refresh cron of manual via refresh_mart_loonkloof RPC.';

-- mart_loonkloof_decomp view opnieuw (was DROP CASCADE hierboven)
create or replace view public.mart_loonkloof_decomp as
with pop as (
    select
        m.legale_entiteit_id,
        m.referentiedatum,
        m.kwartaal,
        m.persoon_id,
        m.geslacht,
        m.functieniveau,
        m.uurloon_bruto,
        m.ancienniteit_jaren,
        case
            when m.ancienniteit_jaren < 2 then 'junior'
            when m.ancienniteit_jaren < 5 then 'medior'
            else 'senior'
        end as ancienniteit_bucket,
        p.opleidingsniveau
    from public.mart_loonkloof m
    join public.dim_persoon p on p.persoon_id = m.persoon_id
),
stratum_stats as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        functieniveau, opleidingsniveau, ancienniteit_bucket, geslacht,
        avg(uurloon_bruto) as avg_uurloon,
        count(*)::int as n,
        coalesce(var_samp(uurloon_bruto), 0) as var_uurloon
    from pop
    group by legale_entiteit_id, referentiedatum, kwartaal,
             functieniveau, opleidingsniveau, ancienniteit_bucket, geslacht
),
per_periode as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        avg(uurloon_bruto) filter (where geslacht = 'm') as gem_uurloon_m,
        avg(uurloon_bruto) filter (where geslacht = 'v') as gem_uurloon_v,
        count(*) filter (where geslacht = 'm')::int as n_m,
        count(*) filter (where geslacht = 'v')::int as n_v,
        coalesce(var_samp(uurloon_bruto) filter (where geslacht = 'm'), 0) as var_m,
        coalesce(var_samp(uurloon_bruto) filter (where geslacht = 'v'), 0) as var_v
    from pop
    group by legale_entiteit_id, referentiedatum, kwartaal
),
strata_match as (
    select
        s_m.legale_entiteit_id, s_m.referentiedatum, s_m.kwartaal,
        (s_m.avg_uurloon - s_v.avg_uurloon) as stratum_gap,
        (s_m.n + s_v.n) as stratum_weight
    from stratum_stats s_m
    join stratum_stats s_v
        using (legale_entiteit_id, referentiedatum, kwartaal,
               functieniveau, opleidingsniveau, ancienniteit_bucket)
    where s_m.geslacht = 'm' and s_v.geslacht = 'v'
),
controlled as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        sum(stratum_gap * stratum_weight) / nullif(sum(stratum_weight), 0) as residual_gap,
        sum(stratum_weight)::int as matched_pop_size
    from strata_match
    group by legale_entiteit_id, referentiedatum, kwartaal
)
select
    p.legale_entiteit_id,
    p.referentiedatum,
    p.kwartaal,
    p.n_m,
    p.n_v,
    round(p.gem_uurloon_m::numeric, 4) as gem_uurloon_m,
    round(p.gem_uurloon_v::numeric, 4) as gem_uurloon_v,
    round((p.gem_uurloon_m - p.gem_uurloon_v)::numeric, 4) as raw_gap,
    round(coalesce(c.residual_gap, 0)::numeric, 4) as residual_gap,
    round(((p.gem_uurloon_m - p.gem_uurloon_v) - coalesce(c.residual_gap, 0))::numeric, 4) as endowment_gap,
    round(
        (1.96 * sqrt(
            case when p.n_m > 0 then p.var_m / p.n_m else 0 end +
            case when p.n_v > 0 then p.var_v / p.n_v else 0 end
        ))::numeric,
        4
    ) as raw_gap_ci95_halfwidth,
    coalesce(c.matched_pop_size, 0) as matched_stratum_pop
from per_periode p
left join controlled c using (legale_entiteit_id, referentiedatum, kwartaal);


-- ================================================================
-- 2. bulk_import_populatie default periode → 2026-06-01
-- ================================================================
create or replace function public.bulk_import_populatie(
    p_legale_entiteit_id uuid,
    p_scenario_id uuid,
    p_rows jsonb,
    p_periode date default '2026-06-01',
    p_geldig_van date default '2025-01-01'
)
    returns table (
        created integer,
        skipped integer,
        errors text[]
    )
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_functie_cache jsonb := '{}'::jsonb;
    v_persoon_id uuid;
    v_contract_id uuid;
    v_functie_id uuid;
    v_created integer := 0;
    v_skipped integer := 0;
    v_errors text[] := '{}';
    v_row record;
    v_existing_functie record;
    v_sqlstate text;
    v_sqlerrm text;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'bulk_import_populatie: authenticated caller required'
            using errcode = '42501';
    end if;

    select owning_account_id into v_owning_account
    from public.dim_legale_entiteit
    where legale_entiteit_id = p_legale_entiteit_id;

    if v_owning_account is null then
        raise exception 'bulk_import_populatie: entiteit % niet gevonden', p_legale_entiteit_id
            using errcode = '02000';
    end if;

    if not basejump.has_role_on_account(v_owning_account) then
        raise exception 'bulk_import_populatie: geen toegang tot deze entiteit'
            using errcode = '42501';
    end if;

    for v_existing_functie in
        select functienaam, functie_id from public.dim_functie where owning_account_id = v_owning_account
    loop
        v_functie_cache := v_functie_cache || jsonb_build_object(
            lower(v_existing_functie.functienaam),
            v_existing_functie.functie_id::text
        );
    end loop;

    for v_row in
        select * from jsonb_to_recordset(p_rows) as x(
            naam text,
            geslacht text,
            geboortedatum date,
            opleidingsniveau text,
            team text,
            status text,
            pc text,
            bruto numeric
        )
    loop
        begin
            if v_row.naam is null or v_row.naam = '' then
                v_errors := v_errors || 'rij zonder naam';
                v_skipped := v_skipped + 1;
                continue;
            end if;
            if v_row.geslacht not in ('m', 'v', 'x') then
                v_errors := v_errors || (v_row.naam || ': ongeldig geslacht');
                v_skipped := v_skipped + 1;
                continue;
            end if;
            if v_row.bruto is null or v_row.bruto <= 0 then
                v_errors := v_errors || (v_row.naam || ': bruto <= 0');
                v_skipped := v_skipped + 1;
                continue;
            end if;

            v_functie_id := (v_functie_cache ->> lower(v_row.team))::uuid;
            if v_functie_id is null then
                insert into public.dim_functie (owning_account_id, functienaam, functieniveau)
                values (v_owning_account, v_row.team, 10)
                returning functie_id into v_functie_id;
                v_functie_cache := v_functie_cache || jsonb_build_object(lower(v_row.team), v_functie_id::text);
            end if;

            insert into public.dim_persoon (owning_account_id, geslacht, geboortedatum, opleidingsniveau)
            values (v_owning_account, v_row.geslacht, v_row.geboortedatum, coalesce(v_row.opleidingsniveau, 'middel_geschoold'))
            returning persoon_id into v_persoon_id;

            insert into public.dim_contract (
                persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van
            )
            values (
                v_persoon_id,
                p_legale_entiteit_id,
                v_functie_id,
                coalesce(v_row.pc, case when v_row.status = 'arbeider' then '124' else '200' end),
                coalesce(v_row.status, 'bediende'),
                1.0,
                p_geldig_van
            )
            returning contract_id into v_contract_id;

            insert into public.fact_looncomponent (
                contract_id, periode, component_id, scenario_id, bedrag
            )
            values (v_contract_id, p_periode, 'basisloon', p_scenario_id, v_row.bruto);

            v_created := v_created + 1;
        exception
            when others then
                get stacked diagnostics v_sqlstate = returned_sqlstate;
                v_sqlerrm := SQLERRM;
                v_errors := v_errors || (
                    coalesce(v_row.naam, '?')
                    || ' [' || v_sqlstate || ']: '
                    || v_sqlerrm
                );
                v_skipped := v_skipped + 1;
                if v_sqlstate ~ '^(53|57|XX)' then
                    raise;
                end if;
        end;
    end loop;

    return query select v_created, v_skipped, v_errors;
end;
$$;
