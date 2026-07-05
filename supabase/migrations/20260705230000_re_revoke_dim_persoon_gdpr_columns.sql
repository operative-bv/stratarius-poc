-- ================================================================
-- ISS-086: herstel GDPR column-level REVOKE op dim_persoon
-- ================================================================
--
-- Migratie 20260703010000 revoked SELECT (geslacht, opleidingsniveau) op
-- dim_persoon van authenticated (T-004 F3 GDPR). Migratie 20260703350000
-- (fix_domain_table_grants) deed daarna een table-level GRANT SELECT wat
-- die REVOKE ongedaan maakte — de columns waren sinds die migratie leesbaar.
--
-- Ontdekt via pgTAP test 21 refactor (ISS-085): test verwachtte 42501 op
-- `SELECT geslacht`, maar kreeg geen exception.
--
-- Fix:
-- 1. RPC `get_oaxaca_persoon_opleiding(uuid[], text)` — SECURITY DEFINER,
--    tenant-check via has_role_on_account op elk persoon's owning_account_id,
--    audit log in gdpr_access_log met rechtsgrondslag.
-- 2. REVOKE SELECT (geslacht, opleidingsniveau) opnieuw.
--
-- Waarom RPC voor opleidingsniveau maar niet voor geslacht: geslacht wordt
-- gelezen via mart_loonkloof (kolom is inline geaggregeerd voor loonkloof
-- analyse), dus dim_persoon.geslacht heeft geen call-site meer. opleidings-
-- niveau is nog nodig in oaxaca-action.ts voor per-persoon strata.
--
-- mart_loonkloof.geslacht blijft leesbaar — dat is by design (aggregate access
-- voor loonkloof context, niet per-persoon lookup).
-- ================================================================

-- ================================================================
-- 1. RPC voor GDPR-safe opleidingsniveau batch lookup
-- ================================================================

create or replace function public.get_oaxaca_persoon_opleiding(
    p_persoon_ids uuid[],
    p_rechtsgrondslag text
)
    returns table (
        persoon_id uuid,
        opleidingsniveau text
    )
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_tenant_account_ids uuid[];
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'get_oaxaca_persoon_opleiding: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'get_oaxaca_persoon_opleiding: p_rechtsgrondslag verplicht (GDPR audit)'
            using errcode = '22023';
    end if;

    -- Verzamel alle account_ids waar caller een role heeft. Filter later
    -- persoon rijen op deze set → cross-tenant leak preventie.
    select array_agg(account_id) into v_tenant_account_ids
    from basejump.account_user
    where user_id = v_initiator;

    if v_tenant_account_ids is null or array_length(v_tenant_account_ids, 1) = 0 then
        -- caller heeft geen account membership → geen data
        return;
    end if;

    -- Audit trail
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator,
            'get_oaxaca_persoon_opleiding',
            array['persoon_id', 'opleidingsniveau'],
            p_rechtsgrondslag,
            coalesce(array_length(p_persoon_ids, 1), 0),
            'read'
        );
    exception
        when others then
            raise warning 'get_oaxaca_persoon_opleiding: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    return query
        select p.persoon_id, p.opleidingsniveau
        from public.dim_persoon p
        where p.persoon_id = any(p_persoon_ids)
          and p.owning_account_id = any(v_tenant_account_ids);
end;
$$;

comment on function public.get_oaxaca_persoon_opleiding(uuid[], text) is
    'ISS-086: GDPR-safe per-persoon opleidingsniveau batch lookup. Tenant check via caller''s account_user memberships (filter cross-tenant persoon_ids). Audit-log met rechtsgrondslag.';

revoke execute on function public.get_oaxaca_persoon_opleiding(uuid[], text) from public;
grant execute on function public.get_oaxaca_persoon_opleiding(uuid[], text) to authenticated;


-- ================================================================
-- 2. Column-level REVOKE opnieuw
-- ================================================================
--
-- Belangrijk: `REVOKE SELECT (geslacht, ...) FROM authenticated` doet niks
-- als het GRANT op TABLE-level was gedaan (Postgres ACL semantiek). We
-- moeten eerst de table-level SELECT revoken, dan expliciet per-kolom
-- grantens (niet-beschermde kolommen).

revoke select on public.dim_persoon from authenticated;
grant select (persoon_id, owning_account_id, geboortedatum, created_at, updated_at)
    on public.dim_persoon to authenticated;

-- mart_loonkloof_decomp view join'd nog op dim_persoon.opleidingsniveau.
-- View owner is postgres, dus RUNS AS postgres → SELECT lukt ondanks REVOKE.
-- Geen wijziging aan die view nodig.
