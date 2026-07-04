-- ================================================================
-- T-056: cascade_populatie_snapshot subset filters via p_filters jsonb
-- ================================================================
--
-- Wijzigingen tov ISS-076 versie:
--   - Signature: p_functie_id uuid → p_filters jsonb default '{}'::jsonb
--   - Filter keys (allemaal optioneel):
--       pc_ids                text[]  — filter op paritair comité
--       statussen             text[]  — arbeider|bediende
--       gewesten              text[]  — vlaanderen|wallonie|brussel
--       functie_ids           uuid[]  — vervangt oude p_functie_id
--       ancienniteit_min_jaren numeric — dienstverband duur min
--       ancienniteit_max_jaren numeric — dienstverband duur max
--       leeftijd_min          int     — persoon leeftijd min
--       leeftijd_max          int     — persoon leeftijd max
--
-- Alle filter-clauses zijn `not (p_filters ? 'key') or <check>` zodat
-- ontbrekende keys geen filtering triggeren. Backward-compat kan mogelijk
-- gemaakt worden door de UI callers p_functie_id te vertalen naar
-- p_filters.functie_ids array — gebeurt in aparte commit.
--
-- Postgres kan RETURNS TABLE + parameters niet CREATE OR REPLACE-en zodra
-- signature wijzigt -> DROP + CREATE.
--
-- Rollback: revert naar 20260704000400_cascade_populatie_snapshot_stap4_in_totaal.sql.


drop function if exists public.cascade_populatie_snapshot(date, uuid, uuid);


create or replace function public.cascade_populatie_snapshot(
    p_periode     date,
    p_scenario_id uuid default null,
    p_filters     jsonb default '{}'::jsonb
)
    returns table (
        contract_id uuid,
        persoon_id uuid,
        pc_id text,
        status text,
        werkgeverscategorie smallint,
        functienaam text,
        mu numeric(6, 4),
        bruto numeric(18, 4),
        stap2_basis_rsz numeric(18, 4),
        stap3_vermindering numeric(18, 4),
        stap4_doelgroep numeric(18, 4),
        stap5_bijzondere numeric(18, 4),
        stap6_vakantiegeld numeric(18, 4),
        stap7_extralegaal numeric(18, 4),
        stap8_wagen numeric(18, 4),
        stap9_arbeidsongevallen numeric(18, 4),
        totaal_patronale_kost numeric(18, 4),
        tco numeric(18, 4)
    )
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    with contracten as (
        select
            c.contract_id,
            c.persoon_id,
            c.pc_id,
            c.status,
            le.werkgeverscategorie,
            le.gewest,
            f.functienaam,
            p.geboortedatum,
            c.geldig_van as dienstverband_van,
            coalesce(public.mu_van_prestatie(c.contract_id, p_periode), 1.0000)::numeric(6, 4) as mu,
            coalesce((
                select sum(fl.bedrag)
                from public.fact_looncomponent fl
                join public.dim_looncomponent dl on dl.component_id = fl.component_id
                where fl.contract_id = c.contract_id
                  and fl.periode = date_trunc('month', p_periode)::date
                  and (p_scenario_id is null or fl.scenario_id = p_scenario_id)
                  and dl.is_basisloon
            ), 0)::numeric(18, 4) as bruto
        from public.dim_contract c
        join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id
        join public.dim_functie f on f.functie_id = c.functie_id
        join public.dim_persoon p on p.persoon_id = c.persoon_id
        where c.geldig_van <= p_periode
          and (c.geldig_tot is null or c.geldig_tot > p_periode)
          -- Filter: pc_ids
          and (not (p_filters ? 'pc_ids')
               or c.pc_id = any (array(select jsonb_array_elements_text(p_filters -> 'pc_ids'))))
          -- Filter: statussen (arbeider|bediende)
          and (not (p_filters ? 'statussen')
               or c.status = any (array(select jsonb_array_elements_text(p_filters -> 'statussen'))))
          -- Filter: gewesten (vlaanderen|wallonie|brussel)
          and (not (p_filters ? 'gewesten')
               or le.gewest = any (array(select jsonb_array_elements_text(p_filters -> 'gewesten'))))
          -- Filter: functie_ids
          and (not (p_filters ? 'functie_ids')
               or c.functie_id = any (array(select (jsonb_array_elements_text(p_filters -> 'functie_ids'))::uuid)))
          -- Filter: ancienniteit_min_jaren (dienstverband duur)
          and (not (p_filters ? 'ancienniteit_min_jaren')
               or extract(year from age(p_periode, c.geldig_van)) >= (p_filters ->> 'ancienniteit_min_jaren')::numeric)
          -- Filter: ancienniteit_max_jaren
          and (not (p_filters ? 'ancienniteit_max_jaren')
               or extract(year from age(p_periode, c.geldig_van)) <= (p_filters ->> 'ancienniteit_max_jaren')::numeric)
          -- Filter: leeftijd_min (persoon leeftijd)
          and (not (p_filters ? 'leeftijd_min')
               or extract(year from age(p_periode, p.geboortedatum)) >= (p_filters ->> 'leeftijd_min')::int)
          -- Filter: leeftijd_max
          and (not (p_filters ? 'leeftijd_max')
               or extract(year from age(p_periode, p.geboortedatum)) <= (p_filters ->> 'leeftijd_max')::int)
    ),
    berekend as (
        select
            ct.contract_id,
            ct.persoon_id,
            ct.pc_id,
            ct.status,
            ct.werkgeverscategorie,
            ct.functienaam,
            ct.mu,
            ct.bruto,
            coalesce(
                public.cascade_stap2_basis_patronale_rsz(ct.bruto, ct.status, ct.werkgeverscategorie, p_periode),
                0
            )::numeric(18, 4) as stap2_basis_rsz,
            coalesce(
                public.cascade_stap3_structurele_vermindering(ct.bruto * 3, ct.mu, ct.werkgeverscategorie, p_periode),
                0
            )::numeric(18, 4) as stap3_vermindering,
            coalesce(
                public.cascade_stap4_doelgroepverminderingen(ct.contract_id, ct.bruto, ct.mu, p_periode),
                0
            )::numeric(18, 4) as stap4_doelgroep,
            coalesce(
                public.cascade_stap5_bijzondere_bijdragen(ct.bruto, p_periode),
                0
            )::numeric(18, 4) as stap5_bijzondere,
            coalesce(
                public.cascade_stap6_vakantiegeld(ct.bruto, ct.status, p_periode),
                0
            )::numeric(18, 4) as stap6_vakantiegeld,
            coalesce((
                select sum(fl.bedrag * pe.taks_pct)
                from public.fact_looncomponent fl
                join public.dim_looncomponent dl on dl.component_id = fl.component_id
                join public.param_extralegaal pe on pe.voordeeltype = dl.component_id
                where fl.contract_id = ct.contract_id
                  and fl.periode = date_trunc('month', p_periode)::date
                  and (p_scenario_id is null or fl.scenario_id = p_scenario_id)
                  and dl.familie = 'extralegaal'
                  and p_periode >= pe.geldig_van
                  and (pe.geldig_tot is null or p_periode < pe.geldig_tot)
            ), 0)::numeric(18, 4) as stap7_extralegaal,
            coalesce((
                select public.cascade_stap8_wagen_solidariteitsbijdrage(fw.co2_g_km, fw.brandstoftype, p_periode)
                from public.fact_wagen fw
                where fw.contract_id = ct.contract_id
                  and fw.periode = date_trunc('month', p_periode)::date
                limit 1
            ), 0)::numeric(18, 4) as stap8_wagen,
            coalesce(
                public.cascade_stap9_arbeidsongevallen(ct.bruto, ct.pc_id, p_periode),
                0
            )::numeric(18, 4) as stap9_arbeidsongevallen
        from contracten ct
    )
    select
        b.contract_id, b.persoon_id, b.pc_id, b.status, b.werkgeverscategorie, b.functienaam,
        b.mu, b.bruto,
        b.stap2_basis_rsz, b.stap3_vermindering, b.stap4_doelgroep,
        b.stap5_bijzondere, b.stap6_vakantiegeld, b.stap7_extralegaal,
        b.stap8_wagen, b.stap9_arbeidsongevallen,
        (
            b.stap2_basis_rsz - b.stap3_vermindering - b.stap4_doelgroep
            + b.stap5_bijzondere + b.stap6_vakantiegeld + b.stap7_extralegaal
            + b.stap8_wagen + b.stap9_arbeidsongevallen
        )::numeric(18, 4) as totaal_patronale_kost,
        (
            b.bruto
            + b.stap2_basis_rsz - b.stap3_vermindering - b.stap4_doelgroep
            + b.stap5_bijzondere + b.stap6_vakantiegeld + b.stap7_extralegaal
            + b.stap8_wagen + b.stap9_arbeidsongevallen
        )::numeric(18, 4) as tco
    from berekend b;
$$;

comment on function public.cascade_populatie_snapshot(date, uuid, jsonb) is
    'Populatie-snapshot met subset filters via p_filters jsonb. Filter keys (allemaal optioneel): pc_ids, statussen, gewesten, functie_ids, ancienniteit_min_jaren, ancienniteit_max_jaren, leeftijd_min, leeftijd_max. Alle contracten in tenant + volledige cascade output (stap 2-9). RLS filtert via dim_contract / dim_legale_entiteit. T-056 vervangt de oude p_functie_id parameter.';

grant execute on function public.cascade_populatie_snapshot(date, uuid, jsonb) to authenticated;
