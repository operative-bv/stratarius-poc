-- ================================================================
-- ISS-081 + ISS-082 — Hardening bulk_import + gdpr_access_log audit
-- ================================================================
--
-- ISS-081: bulk_import_populatie WHEN OTHERS slikt SQLSTATE waardoor
-- data-conflicts en infra-errors ononderscheidbaar zijn. Fix: capture
-- SQLSTATE in de error string + re-raise infra-class errors (53*, 57*,
-- XX*) zodat de client weet dat het geen data-issue is.
--
-- ISS-082: clear_tenant_populatie INSERT INTO gdpr_access_log kan de
-- hele transactie (incl. de deletes) rollbacken als de audit-insert
-- faalt (bijv. check constraint change zoals in 130000 fix). Fix:
-- wrap de audit-insert in eigen BEGIN/EXCEPTION block met RAISE
-- WARNING — de wipe blijft succesvol ook als audit-log tijdelijk
-- gebroken is.
-- ================================================================

-- ================================================================
-- ISS-081: bulk_import_populatie met SQLSTATE capture
-- ================================================================

create or replace function public.bulk_import_populatie(
    p_legale_entiteit_id uuid,
    p_scenario_id uuid,
    p_rows jsonb,
    p_periode date default '2024-06-01',
    p_geldig_van date default '2023-01-01'
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
                -- ISS-081: capture SQLSTATE in error string voor debugging
                v_errors := v_errors || (
                    coalesce(v_row.naam, '?')
                    || ' [' || v_sqlstate || ']: '
                    || v_sqlerrm
                );
                v_skipped := v_skipped + 1;
                -- Re-raise infra-class errors (Class 53 insufficient resources,
                -- 57 operator intervention, XX internal error). Data-conflicts
                -- (Class 23 integrity constraint violation) blijven in de
                -- error array staan zodat de rest van de batch door kan.
                if v_sqlstate ~ '^(53|57|XX)' then
                    raise;
                end if;
        end;
    end loop;

    return query select v_created, v_skipped, v_errors;
end;
$$;

comment on function public.bulk_import_populatie(uuid, uuid, jsonb, date, date) is
    'One-transaction batch insert. Per-row EXCEPTION captures SQLSTATE + SQLERRM. Infra-errors (Class 53/57/XX) re-raised zodat monitoring kan alerten; data-conflicts (Class 23 etc.) blijven in errors array voor per-rij feedback.';


-- ================================================================
-- ISS-082: clear_tenant_populatie met resiliente audit log
-- ================================================================

create or replace function public.clear_tenant_populatie(
    p_legale_entiteit_id uuid,
    p_rechtsgrondslag text default 'user reset via import page'
)
    returns table (
        fact_wagen_deleted int,
        fact_prestatie_deleted int,
        fact_looncomponent_deleted int,
        fact_loonkost_deleted int,
        dim_contract_deleted int,
        dim_persoon_deleted int
    )
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_fw int := 0;
    v_fp int := 0;
    v_fl int := 0;
    v_flk int := 0;
    v_dc int := 0;
    v_dp int := 0;
    v_total_deleted int;
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
        raise exception 'clear_tenant_populatie: geen toegang tot deze entiteit'
            using errcode = '42501';
    end if;

    with deleted as (
        delete from public.fact_wagen fw
        using public.dim_contract c
        where fw.contract_id = c.contract_id
          and c.legale_entiteit_id = p_legale_entiteit_id
        returning 1
    )
    select count(*) into v_fw from deleted;

    with deleted as (
        delete from public.fact_prestatie fp
        using public.dim_contract c
        where fp.contract_id = c.contract_id
          and c.legale_entiteit_id = p_legale_entiteit_id
        returning 1
    )
    select count(*) into v_fp from deleted;

    with deleted as (
        delete from public.fact_looncomponent fl
        using public.dim_contract c
        where fl.contract_id = c.contract_id
          and c.legale_entiteit_id = p_legale_entiteit_id
        returning 1
    )
    select count(*) into v_fl from deleted;

    with deleted as (
        delete from public.fact_loonkost flk
        using public.dim_contract c
        where flk.contract_id = c.contract_id
          and c.legale_entiteit_id = p_legale_entiteit_id
        returning 1
    )
    select count(*) into v_flk from deleted;

    with deleted as (
        delete from public.dim_contract
        where legale_entiteit_id = p_legale_entiteit_id
        returning 1
    )
    select count(*) into v_dc from deleted;

    with deleted as (
        delete from public.dim_persoon p
        where p.owning_account_id = v_owning_account
          and not exists (
              select 1 from public.dim_contract c
              where c.persoon_id = p.persoon_id
          )
        returning 1
    )
    select count(*) into v_dp from deleted;

    v_total_deleted := v_fw + v_fp + v_fl + v_flk + v_dc + v_dp;

    -- ISS-082: audit-insert in eigen exception block. Als het audit-log
    -- schema drift heeft (bijv. gdpr_access_log kolom mismatch zoals in
    -- 20260705130000 fix), moet de wipe SUCCESVOL blijven. RAISE WARNING
    -- geeft de admin een spoor in de logs zonder de transactie te breken.
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator,
            'populatie_wipe',
            array['dim_persoon', 'dim_contract', 'fact_*'],
            p_rechtsgrondslag,
            v_total_deleted,
            'refresh'
        );
    exception
        when others then
            raise warning 'clear_tenant_populatie: audit log insert faalde (rows still deleted): [%] %',
                SQLSTATE, SQLERRM;
    end;

    return query select v_fw, v_fp, v_fl, v_flk, v_dc, v_dp;
end;
$$;

comment on function public.clear_tenant_populatie(uuid, text) is
    'Wist populatie-data voor één legale_entiteit binnen tenant. SECURITY DEFINER + has_role_on_account. Audit log insert in eigen exception block: audit-schema drift breekt de delete niet meer (ISS-082).';
