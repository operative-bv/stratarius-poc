-- ================================================================
-- ISS-094: cache-refresh concurrency safety
-- ================================================================
--
-- Twee callers hit een lege cache tegelijk → beide doen DELETE +
-- INSERT SELECT zonder synchronisatie. Onder READ COMMITTED slagen
-- beide DELETEs (leeg = niets te locken), beide INSERTs starten,
-- tweede caller crash op PK-violation. Cache staat half-gevuld door
-- de eerste caller; tweede caller ziet error + fallback.
--
-- Twee-lagige fix (defense in depth):
-- 1. pg_advisory_xact_lock op hash van (owning_account_id + scenario_id
--    + periode) — serialiseer concurrent refreshes voor DEZELFDE scope.
--    Automatisch vrijgegeven aan einde van transactie.
-- 2. ON CONFLICT DO NOTHING op de INSERT — als een advisory lock
--    ergens gemist wordt (of een third-party writer inspringt), skip
--    silently ipv PK-crash.
--
-- refresh_populatie_loonkost_cache: advisory lock scoped op
-- (owning_account_id, scenario_id, periode).
-- refresh_mart_loonkloof: advisory lock scoped op owning_account_id
-- (mart_loonkloof is periode-onafhankelijk in refresh: alle kwartalen
-- in één call).
-- ================================================================


-- ================================================================
-- 1. refresh_populatie_loonkost_cache — advisory lock + ON CONFLICT
-- ================================================================

create or replace function public.refresh_populatie_loonkost_cache(
    p_periode     date,
    p_scenario_id uuid
)
    returns integer
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator          uuid;
    v_scenario_account   uuid;
    v_rowcount           integer;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'refresh_populatie_loonkost_cache: authenticated caller required'
            using errcode = '42501';
    end if;

    -- Tenant check op scenario_id (bypasst RLS via DEFINER).
    select le.owning_account_id into v_scenario_account
    from public.dim_scenario s
    join public.dim_legale_entiteit le on le.legale_entiteit_id = s.legale_entiteit_id
    where s.scenario_id = p_scenario_id;

    if v_scenario_account is null then
        raise exception 'refresh_populatie_loonkost_cache: scenario % niet gevonden', p_scenario_id
            using errcode = '02000';
    end if;

    if not basejump.has_role_on_account(v_scenario_account) then
        raise exception 'refresh_populatie_loonkost_cache: geen toegang tot scenario %', p_scenario_id
            using errcode = '42501';
    end if;

    -- ISS-094: advisory lock scoped op (tenant, scenario, periode).
    -- Concurrent refreshes voor dezelfde scope wachten op elkaar; verschillende
    -- scopes lopen parallel. Vrijgegeven aan einde transactie.
    perform pg_advisory_xact_lock(
        hashtextextended(
            v_scenario_account::text || p_scenario_id::text || p_periode::text,
            42
        )
    );

    -- Audit log (matcht ISS-082 pattern: eigen exception block).
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator,
            'refresh_populatie_loonkost_cache',
            array['persoon_id', 'geslacht', 'opleidingsniveau'],
            'HR loonkost cache refresh voor scenario ' || p_scenario_id::text,
            0,
            'read'
        );
    exception
        when others then
            raise warning 'refresh_populatie_loonkost_cache: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    -- Delete existing rows voor deze tenant × scenario × periode combinatie.
    delete from public.mart_populatie_loonkost
    where owning_account_id = v_scenario_account
      and scenario_id = p_scenario_id
      and periode = p_periode;

    -- Insert nieuwe cache via cascade_populatie_snapshot output.
    -- ON CONFLICT DO NOTHING als defense-in-depth voor race conditions.
    insert into public.mart_populatie_loonkost (
        contract_id, persoon_id, legale_entiteit_id, owning_account_id,
        scenario_id, periode,
        pc_id, status, werkgeverscategorie, functie_id, functienaam,
        mu, bruto,
        stap2_basis_rsz, stap3_vermindering, stap4_doelgroep,
        stap5_bijzondere, stap6_vakantiegeld, stap7_extralegaal,
        stap8_wagen, stap9_arbeidsongevallen,
        totaal_patronale_kost, tco
    )
    select
        s.contract_id, s.persoon_id,
        c.legale_entiteit_id, v_scenario_account,
        p_scenario_id, p_periode,
        s.pc_id, s.status, s.werkgeverscategorie, c.functie_id, s.functienaam,
        s.mu, s.bruto,
        s.stap2_basis_rsz, s.stap3_vermindering, s.stap4_doelgroep,
        s.stap5_bijzondere, s.stap6_vakantiegeld, s.stap7_extralegaal,
        s.stap8_wagen, s.stap9_arbeidsongevallen,
        s.totaal_patronale_kost, s.tco
    from public.cascade_populatie_snapshot(p_periode, p_scenario_id, '{}'::jsonb) s
    join public.dim_contract c on c.contract_id = s.contract_id
    on conflict (contract_id, scenario_id, periode) do nothing;

    get diagnostics v_rowcount = row_count;
    return v_rowcount;
end;
$$;


-- ================================================================
-- 2. refresh_mart_loonkloof — advisory lock + ON CONFLICT
-- ================================================================

create or replace function public.refresh_mart_loonkloof(
    p_owning_account_id uuid,
    p_rechtsgrondslag   text
)
    returns integer
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_rowcount  integer;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'refresh_mart_loonkloof: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_owning_account_id is null then
        raise exception 'refresh_mart_loonkloof: p_owning_account_id verplicht'
            using errcode = '22023';
    end if;

    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'refresh_mart_loonkloof: p_rechtsgrondslag verplicht (GDPR audit)'
            using errcode = '22023';
    end if;

    if not basejump.has_role_on_account(p_owning_account_id) then
        raise exception 'refresh_mart_loonkloof: geen toegang tot account %', p_owning_account_id
            using errcode = '42501';
    end if;

    -- ISS-094: advisory lock scoped op tenant. Concurrent loonkloof refreshes
    -- voor dezelfde tenant wachten op elkaar; verschillende tenants parallel.
    perform pg_advisory_xact_lock(
        hashtextextended(p_owning_account_id::text, 43)
    );

    -- Audit
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator,
            'refresh_mart_loonkloof',
            array['persoon_id', 'geslacht', 'uurloon_bruto'],
            p_rechtsgrondslag,
            0,
            'read'
        );
    exception
        when others then
            raise warning 'refresh_mart_loonkloof: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    delete from public.mart_loonkloof
    where owning_account_id = p_owning_account_id;

    with kwartaal_eindes as (
        select generate_series('2024-03-31'::date, '2026-12-31'::date, interval '3 months')::date as referentiedatum
    ),
    contract_op_referentie as (
        select
            c.contract_id, c.persoon_id, c.pc_id, c.geldig_van, c.legale_entiteit_id,
            le.owning_account_id,
            f.functieniveau,
            p.geslacht,
            k.referentiedatum
        from public.dim_contract c
        join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id
        join public.dim_functie f on f.functie_id = c.functie_id
        join public.dim_persoon p on p.persoon_id = c.persoon_id
        cross join kwartaal_eindes k
        where c.geldig_van <= k.referentiedatum
          and (c.geldig_tot is null or c.geldig_tot > k.referentiedatum)
          and le.owning_account_id = p_owning_account_id
    ),
    lonen_maand as (
        select
            cr.persoon_id, cr.referentiedatum, cr.pc_id, cr.functieniveau, cr.geslacht,
            cr.geldig_van, cr.legale_entiteit_id, cr.owning_account_id,
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
        group by cr.persoon_id, cr.referentiedatum, cr.pc_id, cr.functieniveau, cr.geslacht, cr.geldig_van, cr.legale_entiteit_id, cr.owning_account_id
    )
    insert into public.mart_loonkloof (
        persoon_id, legale_entiteit_id, owning_account_id,
        referentiedatum, kwartaal,
        uurloon_bruto, basis_vte, variabele_vte,
        geslacht, functieniveau, ancienniteit_jaren
    )
    select
        lm.persoon_id,
        lm.legale_entiteit_id,
        lm.owning_account_id,
        lm.referentiedatum,
        extract(year from lm.referentiedatum)::text || '-Q' || extract(quarter from lm.referentiedatum)::text,
        public.uurloon_van_maandloon(lm.basis_vte, lm.pc_id, lm.referentiedatum),
        lm.basis_vte,
        lm.variabele_vte,
        lm.geslacht,
        lm.functieniveau,
        round(((lm.referentiedatum - lm.geldig_van)::numeric / 365.25), 2)::numeric(6, 2)
    from lonen_maand lm
    on conflict (persoon_id, referentiedatum) do nothing;

    get diagnostics v_rowcount = row_count;
    return v_rowcount;
end;
$$;
