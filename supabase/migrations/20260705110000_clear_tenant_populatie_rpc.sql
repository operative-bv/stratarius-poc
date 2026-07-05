-- ================================================================
-- clear_tenant_populatie RPC — wist alle dim_persoon + dim_contract +
-- fact_* rijen voor een specifieke legale_entiteit binnen de tenant
-- van de aanroepende user.
-- ================================================================
--
-- Gebruikt op de import page voor "reset populatie" workflow. Nuttig
-- na een demo-dataset load die je wilt vervangen door echte data.
--
-- Behoudt:
--   - dim_legale_entiteit zelf (organisatie blijft bestaan)
--   - dim_functie (teams — mogelijk hergebruikt bij nieuwe import)
--   - dim_scenario baseline (nodig voor nieuwe import)
--   - param_* (globale parameters, niet-tenant)
--
-- Verwijdert in FK-orde:
--   1. fact_wagen, fact_prestatie, fact_looncomponent, fact_loonkost
--   2. dim_contract
--   3. dim_persoon
--
-- Security: SECURITY DEFINER + expliciete check dat de caller een
-- role heeft op de owning_account_id van de opgegeven entiteit.
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
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'clear_tenant_populatie: authenticated caller required'
            using errcode = '42501';
    end if;

    -- Lookup owning_account voor deze entiteit en check role
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

    -- Verwijderen in FK-volgorde
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

    -- dim_persoon: alleen personen zonder overgebleven contracten wissen
    -- (persoon kan in theorie ook los van deze entiteit contracten hebben).
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

    -- Audit log
    insert into public.gdpr_access_log (initiator_user_id, resource, rechtsgrondslag)
    values (v_initiator, 'clear_tenant_populatie', p_rechtsgrondslag);

    return query select v_fw, v_fp, v_fl, v_flk, v_dc, v_dp;
end;
$$;

revoke execute on function public.clear_tenant_populatie(uuid, text) from public;
grant execute on function public.clear_tenant_populatie(uuid, text) to authenticated;

comment on function public.clear_tenant_populatie(uuid, text) is
    'Wist populatie-data (fact_* + dim_contract + dim_persoon zonder overgebleven contracten) voor één legale_entiteit binnen tenant van de caller. SECURITY DEFINER met expliciete has_role_on_account check. Behoudt dim_functie, dim_scenario, dim_legale_entiteit.';
