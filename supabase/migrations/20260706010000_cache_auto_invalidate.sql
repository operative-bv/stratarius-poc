-- ================================================================
-- Auto-invalidate mart_populatie_loonkost bij mutatie-RPCs
-- ================================================================
--
-- Design keuze: we weten zelf wanneer de cascade-input data verandert
-- (contracten importeren/wissen, scenario aanmaken). De user hoeft geen
-- Refresh cache button te klikken — invalidation is een architecturaal
-- side effect van elke mutatie-RPC.
--
-- Betroken RPCs:
-- - bulk_import_populatie: nieuwe contracten → alle tenant caches stale
-- - clear_tenant_populatie: contracten weg → alle tenant caches stale
--
-- Scenario-specifieke mutaties (loon-mutatie createScenario, create_simulator_scenario)
-- creëren een NIEUW scenario_id, dus er is nooit al cache voor. Geen invalidation nodig.
--
-- Parameter migraties: rare event; als we die uitrollen doen we handmatig een
-- global TRUNCATE mart_populatie_loonkost via de migration zelf.
-- ================================================================

-- ================================================================
-- 1. bulk_import_populatie: invalidate cache aan eind
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

    -- Cache invalidate: nieuwe contracten betekenen dat alle cache-entries
    -- voor deze tenant achterhaald zijn. Volgende page-load triggert auto-refresh.
    delete from public.mart_populatie_loonkost
    where owning_account_id = v_owning_account;

    return query select v_created, v_skipped, v_errors;
end;
$$;


-- ================================================================
-- 2. clear_tenant_populatie: invalidate cache aan eind
-- ================================================================
-- Bestaande signature ophalen en aanvullen met cache-delete. Volledig
-- overschrijven omdat de body meerdere DELETEs doet.

create or replace function public.clear_tenant_populatie(
    p_legale_entiteit_id uuid
)
    returns table (
        deleted_contracten integer,
        deleted_personen integer
    )
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_deleted_contracten integer := 0;
    v_deleted_personen integer := 0;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'clear_tenant_populatie: authenticated caller required'
            using errcode = '42501';
    end if;

    select owning_account_id into v_owning_account
    from public.dim_legale_entiteit
    where legale_entiteit_id = p_legale_entiteit_id;

    if v_owning_account is null then
        raise exception 'clear_tenant_populatie: entiteit % niet gevonden', p_legale_entiteit_id
            using errcode = '02000';
    end if;

    if not basejump.has_role_on_account(v_owning_account) then
        raise exception 'clear_tenant_populatie: geen toegang tot entiteit %', p_legale_entiteit_id
            using errcode = '42501';
    end if;

    -- Audit trail
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator,
            'clear_tenant_populatie',
            array['contract_id', 'persoon_id'],
            'HR data cleanup — user request',
            0,
            'delete'
        );
    exception
        when others then
            raise warning 'clear_tenant_populatie: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    -- Cache first (voor FK cascade orde)
    delete from public.mart_populatie_loonkost
    where owning_account_id = v_owning_account;

    -- fact_loonkost (persisted cascade output)
    delete from public.fact_loonkost
    where contract_id in (
        select contract_id from public.dim_contract
        where legale_entiteit_id = p_legale_entiteit_id
    );

    -- fact_prestatie, fact_wagen, fact_looncomponent
    delete from public.fact_prestatie
    where contract_id in (
        select contract_id from public.dim_contract
        where legale_entiteit_id = p_legale_entiteit_id
    );
    delete from public.fact_wagen
    where contract_id in (
        select contract_id from public.dim_contract
        where legale_entiteit_id = p_legale_entiteit_id
    );
    delete from public.fact_looncomponent
    where contract_id in (
        select contract_id from public.dim_contract
        where legale_entiteit_id = p_legale_entiteit_id
    );

    -- Contracten + hun tellend delete
    with deleted as (
        delete from public.dim_contract
        where legale_entiteit_id = p_legale_entiteit_id
        returning persoon_id
    )
    select count(*) into v_deleted_contracten from deleted;

    -- Wees-personen (geen contract meer) verwijderen
    with deleted as (
        delete from public.dim_persoon p
        where p.owning_account_id = v_owning_account
          and not exists (
            select 1 from public.dim_contract c where c.persoon_id = p.persoon_id
          )
        returning p.persoon_id
    )
    select count(*) into v_deleted_personen from deleted;

    return query select v_deleted_contracten, v_deleted_personen;
end;
$$;


comment on function public.bulk_import_populatie(uuid, uuid, jsonb, date, date) is
    'Bulk import van populatie CSV rijen. Invalidateert automatisch mart_populatie_loonkost cache voor deze tenant aan het eind. GDPR audit + SQLSTATE re-raise voor infra errors.';

comment on function public.clear_tenant_populatie(uuid) is
    'Wis alle contracten + personen voor deze tenant. Invalidateert automatisch mart_populatie_loonkost cache + fact_loonkost. GDPR audit met event_kind=delete.';
