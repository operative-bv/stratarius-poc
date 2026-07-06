-- ================================================================
-- ISS-101: refresh-vs-mutation race — gedeelde advisory lock namespace
-- ================================================================
--
-- Codex ronde 2 I2 (93/100). ISS-094 advisory lock in refresh RPCs
-- serialiseert refreshes onderling. Trigger-based invalidatie neemt
-- dezelfde lock niet. Race scenario:
--
-- 1. A begint refresh_populatie_loonkost_cache, holds lock hash(tenant, scenario, periode).
-- 2. A doet DELETE FROM mart (rows verwijderd).
-- 3. A begint langzame cascade computation (SELECT fact_looncomponent).
-- 4. B doet INSERT fact_looncomponent (nieuwe waarde).
-- 5. B's trigger DELETE FROM mart (no-op want cache al leeg).
-- 6. B commit — mart weer leeg, fact_looncomponent heeft nieuwe rij.
-- 7. A's cascade read: onder READ COMMITTED ziet A B's commit niet
--    (snapshot was voor B's commit).
-- 8. A INSERT met OUDE data.
-- 9. A commit met stale mart die "vers" lijkt (refreshed_at recent) —
--    auto-populate triggert niet meer, cache blijft indefinitely stale.
--
-- Fix: invalidation-trigger neemt ZELFDE advisory lock als refresh-RPC.
-- Trigger die tegelijk met een refresh wordt getriggerd wacht op de refresh.
-- Refresh's SELECT ziet vervolgens ALLE gecommitte mutations.
--
-- Belangrijke design-keuze: lock in AFTER trigger blocks mutation commit.
-- Voor bulk_import scenario met veel rows: acceptabel — mutations moeten
-- niet parallel met refresh lopen anyway.
-- ================================================================


-- ================================================================
-- 1. Trigger function: neem OOK advisory lock per tenant vóór DELETE
-- ================================================================
--
-- Salt 42 = populatie-loonkost scope. We locken alleen op tenant-niveau
-- (owning_account) omdat de trigger niet weet welke scenario/periode
-- combi wordt geraakt. Refresh-RPC lockt op (tenant, scenario, periode).
-- Om deadlock te voorkomen tussen trigger (lockt breed op tenant) en
-- refresh (lockt specifiek op scope): gebruik apart hash-salt voor
-- trigger-lock EN refresh-lock, maar zorg dat trigger óók de refresh-locks
-- probeert vast te grijpen door pg_advisory_xact_lock op tenant-salt te
-- nemen.
--
-- Simpelere aanpak: refresh-RPCs nemen ÓÓK de tenant-brede lock (salt 42)
-- voordat ze de scoped lock nemen. Trigger neemt alleen de tenant-brede
-- lock. Consistente lock-order voorkomt deadlock.
-- ================================================================

create or replace function public.invalidate_marts_for_owning_account()
    returns trigger
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_accounts uuid[];
    v_account uuid;
begin
    if TG_TABLE_NAME in ('fact_looncomponent', 'fact_prestatie', 'fact_wagen') then
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r
            join public.dim_contract c on c.contract_id = r.contract_id
            join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from (
                select contract_id from old_rows
                union
                select contract_id from new_rows
            ) r
            join public.dim_contract c on c.contract_id = r.contract_id
            join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r
            join public.dim_contract c on c.contract_id = r.contract_id
            join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME = 'dim_contract' then
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from (select legale_entiteit_id from old_rows union select legale_entiteit_id from new_rows) r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME = 'dim_scenario' then
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from (select legale_entiteit_id from old_rows union select legale_entiteit_id from new_rows) r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME in ('dim_persoon', 'dim_functie') then
        if TG_OP = 'DELETE' then
            select array_agg(distinct owning_account_id) into v_accounts from old_rows;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct owning_account_id) into v_accounts
            from (select owning_account_id from old_rows union select owning_account_id from new_rows) r;
        else
            select array_agg(distinct owning_account_id) into v_accounts from new_rows;
        end if;

    elsif TG_TABLE_NAME = 'dim_legale_entiteit' then
        if TG_OP = 'DELETE' then
            select array_agg(distinct owning_account_id) into v_accounts from old_rows;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct owning_account_id) into v_accounts
            from (select owning_account_id from old_rows union select owning_account_id from new_rows) r;
        else
            select array_agg(distinct owning_account_id) into v_accounts from new_rows;
        end if;
    end if;

    if v_accounts is not null and array_length(v_accounts, 1) > 0 then
        -- ISS-101: neem tenant-brede advisory lock per affected account.
        -- Zelfde lock die refresh-RPCs ook eerst pakken (salt 40 = "cache-tenant-lock").
        -- Als een refresh op deze tenant loopt, wacht deze mutation-invalidation
        -- op de refresh. Refresh's SELECT ziet vervolgens deze commit niet
        -- (snapshot isolation), wat correct is: cache wordt vervolgens door
        -- de trigger's DELETE weer leeggemaakt, en de eerstvolgende page-visit
        -- triggert nieuwe refresh met alle actuele data.
        foreach v_account in array v_accounts loop
            perform pg_advisory_xact_lock(hashtextextended(v_account::text, 40));
        end loop;

        delete from public.mart_populatie_loonkost
        where owning_account_id = any(v_accounts);

        delete from public.mart_loonkloof
        where owning_account_id = any(v_accounts);
    end if;

    return null;
end;
$$;


-- ================================================================
-- 2. refresh_populatie_loonkost_cache: neem ÓÓK tenant-lock vóór scope-lock
-- ================================================================
-- Consistente lock-order (tenant salt=40 eerst, dan scope salt=42) voorkomt
-- deadlock met de trigger-lock hierboven.

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

    -- ISS-101: eerst tenant-brede lock (salt 40), dan scope-specifieke lock (salt 42).
    -- Consistente lock-order met trigger voorkomt deadlock. Trigger neemt alleen
    -- salt-40 lock; refresh neemt salt-40 EN salt-42.
    perform pg_advisory_xact_lock(hashtextextended(v_scenario_account::text, 40));
    perform pg_advisory_xact_lock(
        hashtextextended(
            v_scenario_account::text || p_scenario_id::text || p_periode::text,
            42
        )
    );

    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator, 'refresh_populatie_loonkost_cache',
            array['persoon_id', 'geslacht', 'opleidingsniveau'],
            'HR loonkost cache refresh voor scenario ' || p_scenario_id::text,
            0, 'read'
        );
    exception
        when others then
            raise warning 'refresh_populatie_loonkost_cache: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    delete from public.mart_populatie_loonkost
    where owning_account_id = v_scenario_account
      and scenario_id = p_scenario_id
      and periode = p_periode;

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
-- 3. refresh_mart_loonkloof: neem ÓÓK tenant-lock (salt 40) vóór scope-lock (salt 43)
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

    -- ISS-101: tenant-brede lock (salt 40) — consistent met trigger.
    -- Scope lock (salt 43) daarna voor concurrent loonkloof-refresh serialisatie.
    perform pg_advisory_xact_lock(hashtextextended(p_owning_account_id::text, 40));
    perform pg_advisory_xact_lock(hashtextextended(p_owning_account_id::text, 43));

    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator, 'refresh_mart_loonkloof',
            array['persoon_id', 'geslacht', 'uurloon_bruto'],
            p_rechtsgrondslag, 0, 'read'
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
            le.owning_account_id, f.functieniveau, p.geslacht,
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
    lonen_per_contract as (
        select
            cr.contract_id, cr.persoon_id, cr.referentiedatum, cr.pc_id,
            cr.functieniveau, cr.geslacht, cr.geldig_van, cr.legale_entiteit_id,
            cr.owning_account_id,
            coalesce(sum(fl.bedrag) filter (where dl.is_basisloon), 0)::numeric(18, 4) as basis_vte,
            coalesce(sum(fl.bedrag) filter (where dl.rsz_plichtig and not dl.is_basisloon), 0)::numeric(18, 4) as variabele_vte
        from contract_op_referentie cr
        left join public.fact_looncomponent fl
            on fl.contract_id = cr.contract_id
            and fl.periode = date_trunc('month', cr.referentiedatum)::date
            and fl.scenario_id in (
                select s.scenario_id from public.dim_scenario s
                where s.kind = 'baseline' and s.legale_entiteit_id = cr.legale_entiteit_id
            )
        left join public.dim_looncomponent dl on dl.component_id = fl.component_id
        group by cr.contract_id, cr.persoon_id, cr.referentiedatum, cr.pc_id,
                 cr.functieniveau, cr.geslacht, cr.geldig_van, cr.legale_entiteit_id,
                 cr.owning_account_id
    ),
    lonen_per_persoon as (
        select distinct on (persoon_id, referentiedatum)
            persoon_id, referentiedatum,
            pc_id, functieniveau, geslacht, geldig_van, legale_entiteit_id, owning_account_id,
            sum(basis_vte)     over (partition by persoon_id, referentiedatum) as basis_vte,
            sum(variabele_vte) over (partition by persoon_id, referentiedatum) as variabele_vte
        from lonen_per_contract
        order by persoon_id, referentiedatum, basis_vte desc, contract_id
    )
    insert into public.mart_loonkloof (
        persoon_id, legale_entiteit_id, owning_account_id,
        referentiedatum, kwartaal,
        uurloon_bruto, basis_vte, variabele_vte,
        geslacht, functieniveau, ancienniteit_jaren
    )
    select
        lp.persoon_id, lp.legale_entiteit_id, lp.owning_account_id,
        lp.referentiedatum,
        extract(year from lp.referentiedatum)::text || '-Q' || extract(quarter from lp.referentiedatum)::text,
        public.uurloon_van_maandloon(lp.basis_vte, lp.pc_id, lp.referentiedatum),
        lp.basis_vte, lp.variabele_vte,
        lp.geslacht, lp.functieniveau,
        round(((lp.referentiedatum - lp.geldig_van)::numeric / 365.25), 2)::numeric(6, 2)
    from lonen_per_persoon lp
    on conflict (persoon_id, referentiedatum) do nothing;

    get diagnostics v_rowcount = row_count;
    return v_rowcount;
end;
$$;
