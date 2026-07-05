-- ================================================================
-- Fix clear_tenant_populatie — gdpr_access_log kolomnamen
-- ================================================================
--
-- Vorige migration (20260705110000) gebruikte (initiator_user_id,
-- resource, rechtsgrondslag) maar de tabel heeft (user_id, resource_ref,
-- columns_accessed, rechtsgrondslag, resulting_rows, event_kind).
-- Symptoom: 'column "initiator_user_id" of relation "gdpr_access_log"
-- does not exist' bij wissen populatie.
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

    -- Audit trail met correcte kolomnamen (event_kind = 'refresh' want
    -- de check constraint accepteert alleen 'read' of 'refresh'; delete
    -- past semantisch bij refresh want populatie wordt gereset).
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

    return query select v_fw, v_fp, v_fl, v_flk, v_dc, v_dp;
end;
$$;
