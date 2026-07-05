-- ================================================================
-- ISS-086 vervolg: cascade_populatie_snapshot → SECURITY DEFINER
-- ================================================================
--
-- Context: ISS-086 herstelde de column-level REVOKE op dim_persoon
-- (geslacht, opleidingsniveau). cascade_populatie_snapshot was SECURITY
-- INVOKER met nested SQL functies (cascade_stap4 etc) die dim_persoon
-- protected columns joinen — die faalden met 42501 na de REVOKE.
--
-- Gedetecteerd tijdens pgTAP test 46 refactor (ISS-085): direct psql
-- reproductie bewees dat de populatie page op prod gebroken was sinds
-- de ISS-086 push (2e58883).
--
-- Fix (patroon matcht mart_loonkloof_decomp_read + get_oaxaca_persoon_opleiding):
-- 1. SECURITY DEFINER → hele call stack draait als postgres owner, bypasst
--    de column-REVOKE. Nested SECURITY INVOKER sub-functies erven de context.
-- 2. auth.uid() null-check → alleen authenticated calls.
-- 3. has_role_on_account check op p_scenario_id → cross-tenant preventie
--    (bypasst normaal via RLS, nu handmatig).
-- 4. Tenant-filter in contracten CTE → alleen contracten in caller's accounts.
-- 5. gdpr_access_log audit → rechtsgrondslag afgedwongen ipv column-REVOKE
--    (die alsnog blijft als defense-in-depth voor directe queries).
--
-- Follow-up (nieuwe issue ISS-087): REVOKE EXECUTE op cascade_stap1-9 van
-- authenticated. Nu kunnen users nog steeds die functies direct callen en
-- zo de audit ontwijken. Escape-hatch sluiten maakt GDPR architecturaal.
-- ================================================================

drop function if exists public.cascade_populatie_snapshot(date, uuid, jsonb);


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
    language plpgsql
    security definer
    -- VOLATILE (default) omdat de audit-log insert side-effect heeft.
    -- Voorheen STABLE, maar dat verbiedt INSERT binnen de body.
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_scenario_account uuid;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'cascade_populatie_snapshot: authenticated caller required'
            using errcode = '42501';
    end if;

    -- Tenant check: als scenario_id opgegeven, verifieer dat caller toegang
    -- heeft tot de owning tenant. Anders kunnen ze via dit RPC de cascade
    -- output van een ander tenant zien (SECURITY DEFINER bypasst RLS).
    if p_scenario_id is not null then
        select le.owning_account_id into v_scenario_account
        from public.dim_scenario s
        join public.dim_legale_entiteit le on le.legale_entiteit_id = s.legale_entiteit_id
        where s.scenario_id = p_scenario_id;

        if v_scenario_account is null then
            raise exception 'cascade_populatie_snapshot: scenario % niet gevonden', p_scenario_id
                using errcode = '02000';
        end if;

        if not basejump.has_role_on_account(v_scenario_account) then
            raise exception 'cascade_populatie_snapshot: geen toegang tot scenario %', p_scenario_id
                using errcode = '42501';
        end if;
    end if;

    -- GDPR audit (ISS-082 pattern: eigen exception block zodat audit-drift
    -- de read niet breekt).
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator,
            'cascade_populatie_snapshot',
            array['persoon_id', 'geboortedatum', 'geslacht', 'opleidingsniveau'],
            'HR loonkost analyse via RSZ 9-stappen cascade (POC demo populatie snapshot)',
            0,
            'read'
        );
    exception
        when others then
            raise warning 'cascade_populatie_snapshot: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    return query
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
            -- mu_van_prestatie geeft 0 (niet NULL) wanneer contract geen fact_prestatie
            -- rijen heeft. nullif() converteert die 0 naar NULL zodat coalesce naar
            -- 1.0000 valt (voltijd-aanname).
            coalesce(nullif(public.mu_van_prestatie(c.contract_id, p_periode), 0), 1.0000)::numeric(6, 4) as mu,
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
          -- ISS-086 tenant filter (SECURITY DEFINER bypasst RLS, dus handmatig)
          and (
              (p_scenario_id is not null and le.owning_account_id = v_scenario_account)
              or (p_scenario_id is null and basejump.has_role_on_account(le.owning_account_id))
          )
          -- Filter: pc_ids
          and (not (p_filters ? 'pc_ids')
               or c.pc_id = any (array(select jsonb_array_elements_text(p_filters -> 'pc_ids'))))
          -- Filter: statussen (arbeider|bediende)
          and (not (p_filters ? 'statussen')
               or c.status = any (array(select jsonb_array_elements_text(p_filters -> 'statussen'))))
          -- Filter: gewesten
          and (not (p_filters ? 'gewesten')
               or le.gewest = any (array(select jsonb_array_elements_text(p_filters -> 'gewesten'))))
          -- Filter: functie_ids
          and (not (p_filters ? 'functie_ids')
               or c.functie_id = any (array(select (jsonb_array_elements_text(p_filters -> 'functie_ids'))::uuid)))
          -- Filter: ancienniteit_min_jaren
          and (not (p_filters ? 'ancienniteit_min_jaren')
               or extract(year from age(p_periode, c.geldig_van)) >= (p_filters ->> 'ancienniteit_min_jaren')::numeric)
          -- Filter: ancienniteit_max_jaren
          and (not (p_filters ? 'ancienniteit_max_jaren')
               or extract(year from age(p_periode, c.geldig_van)) <= (p_filters ->> 'ancienniteit_max_jaren')::numeric)
          -- Filter: leeftijd_min
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
end;
$$;

comment on function public.cascade_populatie_snapshot(date, uuid, jsonb) is
    'Populatie-snapshot met cascade RSZ 9-stappen. SECURITY DEFINER met auth.uid()+has_role_on_account tenant check en gdpr_access_log audit (ISS-086 vervolg). Sub-cascade functies erven de postgres-context.';

revoke execute on function public.cascade_populatie_snapshot(date, uuid, jsonb) from public;
grant execute on function public.cascade_populatie_snapshot(date, uuid, jsonb) to authenticated;
