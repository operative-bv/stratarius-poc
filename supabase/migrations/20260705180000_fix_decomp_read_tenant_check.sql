-- ================================================================
-- ISS-083: mart_loonkloof_decomp_read tenant check
-- ================================================================
--
-- Root: SECURITY DEFINER RPC met auth.uid()-check maar géén validatie
-- dat de opgegeven p_legale_entiteit_id bij caller's tenant hoort.
-- User in tenant A kan tenant B's UUID passeren → krijgt tenant B's
-- aggregate loonkloof-cijfers.
--
-- Ook (side fix): de gdpr_access_log INSERT gebruikt oude kolomnamen
-- (initiator_user_id, resource) die niet bestaan — was al gedeeltelijk
-- gefixt in 20260705130000 voor clear_tenant_populatie. Nu ook hier.
--
-- Fix:
-- 1. Lookup owning_account_id via dim_legale_entiteit
-- 2. has_role_on_account check (analoog aan clear_tenant_populatie)
-- 3. Als p_legale_entiteit_id NULL: filter op alle tenant entiteiten
--    ipv alle-tenant leak
-- 4. gdpr_access_log INSERT met correcte kolommen + eigen exception
--    block (ISS-082 pattern)
-- ================================================================

create or replace function public.mart_loonkloof_decomp_read(
    p_rechtsgrondslag text,
    p_legale_entiteit_id uuid default null,
    p_kwartaal text default null
)
    returns setof public.mart_loonkloof_decomp
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_tenant_entiteit_ids uuid[];
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'mart_loonkloof_decomp_read: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'mart_loonkloof_decomp_read: p_rechtsgrondslag is verplicht (GDPR audit)'
            using errcode = '22023';
    end if;

    -- ISS-083: expliciete tenant check op p_legale_entiteit_id
    if p_legale_entiteit_id is not null then
        select owning_account_id into v_owning_account
        from public.dim_legale_entiteit
        where legale_entiteit_id = p_legale_entiteit_id;

        if v_owning_account is null then
            raise exception 'mart_loonkloof_decomp_read: entiteit % niet gevonden', p_legale_entiteit_id
                using errcode = '02000';
        end if;

        if not basejump.has_role_on_account(v_owning_account) then
            raise exception 'mart_loonkloof_decomp_read: geen toegang tot entiteit %', p_legale_entiteit_id
                using errcode = '42501';
        end if;
    else
        -- p_legale_entiteit_id NULL: filter op alle entiteiten die caller
        -- mag zien (RLS op dim_legale_entiteit doet het werk).
        select array_agg(legale_entiteit_id) into v_tenant_entiteit_ids
        from public.dim_legale_entiteit;
    end if;

    -- Audit trail (ISS-082 pattern: eigen exception block zodat
    -- audit-schema drift de read niet breekt)
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator,
            'mart_loonkloof_decomp_read',
            array['legale_entiteit_id', 'kwartaal', 'gem_uurloon_m', 'gem_uurloon_v'],
            p_rechtsgrondslag,
            0, -- rows count niet trivial vooraf; kan later verrijkt met GET DIAGNOSTICS
            'read'
        );
    exception
        when others then
            raise warning 'mart_loonkloof_decomp_read: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    return query
        select d.*
        from public.mart_loonkloof_decomp d
        where (
            (p_legale_entiteit_id is not null and d.legale_entiteit_id = p_legale_entiteit_id)
            or (p_legale_entiteit_id is null and d.legale_entiteit_id = any(v_tenant_entiteit_ids))
        )
        and (p_kwartaal is null or d.kwartaal = p_kwartaal);
end;
$$;

comment on function public.mart_loonkloof_decomp_read(text, uuid, text) is
    'Rechtsgrondslag-gated read op mart_loonkloof_decomp. ISS-083 fix: expliciete has_role_on_account check op p_legale_entiteit_id, of tenant-filter via dim_legale_entiteit RLS bij NULL parameter. Audit-insert in eigen exception block (ISS-082 pattern).';
