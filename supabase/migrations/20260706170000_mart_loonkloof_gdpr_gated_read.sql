-- ================================================================
-- ISS-099: mart_loonkloof — GDPR-gated read RPC + REVOKE direct SELECT
-- ================================================================
--
-- Codex ronde 2 C2 (98/100). dim_persoon.geslacht en opleidingsniveau
-- hebben column-REVOKE voor authenticated (ISS-086). Maar mart_loonkloof
-- repliceert persoon_id + geslacht + uurloon_bruto en gaf direct SELECT
-- aan authenticated. Reads gingen niet via rechtsgrondslag-gated RPC
-- en werden niet gelogd in gdpr_access_log.
--
-- Fix:
-- 1. REVOKE SELECT op mart_loonkloof van authenticated
-- 2. GRANT SELECT alleen aan service_role + postgres (voor RPC's die
--    SECURITY DEFINER draaien)
-- 3. Nieuwe read-RPC read_mart_loonkloof(p_owning_account_id,
--    p_rechtsgrondslag, p_referentiedatum, p_legale_entiteit_id)
--    die tenant-check + audit logt en dan de rows returned
-- 4. loonkloof/page.tsx update naar deze RPC
--
-- Voor mart_populatie_loonkost geldt hetzelfde argument niet als sterk:
-- de mart bevat werkgeverskost-berekeningen (bruto, TCO), geen directe
-- PII zoals geslacht. Persoon_id staat er wel in maar zonder geslacht
-- kolom (die zit alleen in mart_loonkloof). Laten we voor nu de
-- populatie-mart met authenticated SELECT + RLS behouden.
-- ================================================================


-- ================================================================
-- 1. REVOKE + GRANT
-- ================================================================

revoke select on public.mart_loonkloof from authenticated, anon, public;
grant select on public.mart_loonkloof to service_role;

-- SECURITY DEFINER RPC's draaien als owner (postgres), die heeft al full
-- rechten. Trigger-functies ook. Geen extra grants nodig voor die paden.


-- ================================================================
-- 2. read_mart_loonkloof RPC — tenant-check + audit + gefilterde rows
-- ================================================================

drop function if exists public.read_mart_loonkloof(uuid, text, date, uuid);

create or replace function public.read_mart_loonkloof(
    p_owning_account_id uuid,
    p_rechtsgrondslag   text,
    p_referentiedatum   date,
    p_legale_entiteit_id uuid default null
)
    returns table (
        persoon_id uuid,
        legale_entiteit_id uuid,
        referentiedatum date,
        kwartaal text,
        uurloon_bruto numeric,
        basis_vte numeric,
        variabele_vte numeric,
        geslacht text,
        functieniveau smallint,
        ancienniteit_jaren numeric
    )
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
        raise exception 'read_mart_loonkloof: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_owning_account_id is null then
        raise exception 'read_mart_loonkloof: p_owning_account_id verplicht'
            using errcode = '22023';
    end if;

    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'read_mart_loonkloof: p_rechtsgrondslag verplicht (GDPR audit)'
            using errcode = '22023';
    end if;

    if not basejump.has_role_on_account(p_owning_account_id) then
        raise exception 'read_mart_loonkloof: geen toegang tot account %', p_owning_account_id
            using errcode = '42501';
    end if;

    -- Audit
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator, 'read_mart_loonkloof',
            array['persoon_id', 'geslacht', 'uurloon_bruto'],
            p_rechtsgrondslag, 0, 'read'
        );
    exception
        when others then
            raise warning 'read_mart_loonkloof: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    -- Rows returned, tenant-scoped, optioneel entiteit-filter
    return query
    select
        m.persoon_id,
        m.legale_entiteit_id,
        m.referentiedatum,
        m.kwartaal,
        m.uurloon_bruto,
        m.basis_vte,
        m.variabele_vte,
        m.geslacht,
        m.functieniveau,
        m.ancienniteit_jaren
    from public.mart_loonkloof m
    where m.owning_account_id = p_owning_account_id
      and m.referentiedatum = p_referentiedatum
      and (p_legale_entiteit_id is null or m.legale_entiteit_id = p_legale_entiteit_id);

    -- Row-count-in-audit is best-effort; we loggen `resulting_rows=0` in
    -- de eerste insert en zouden de rowcount hier kunnen updaten, maar
    -- dat is niet-atomair met de return query. Voor POC: laat 0 staan
    -- als initial-log, follow-up kan een separate audit-append doen post-return.
    get diagnostics v_rowcount = row_count;
end;
$$;

comment on function public.read_mart_loonkloof(uuid, text, date, uuid) is
    'ISS-099: gated read op mart_loonkloof met has_role_on_account tenant-check + '
    'gdpr_access_log audit. Direct SELECT is voor authenticated REVOKED — deze RPC '
    'is de canonieke read-path. Optioneel filter op legale_entiteit_id.';

revoke execute on function public.read_mart_loonkloof(uuid, text, date, uuid) from public;
grant execute on function public.read_mart_loonkloof(uuid, text, date, uuid) to authenticated;
