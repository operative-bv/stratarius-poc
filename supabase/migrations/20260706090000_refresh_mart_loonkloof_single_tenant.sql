-- ================================================================
-- ISS-091: refresh_mart_loonkloof — single-tenant scope
-- ================================================================
--
-- Oude versie fetched ALLE tenants van de caller via
-- `select array_agg(account_id) from basejump.account_user
--  where user_id = auth.uid()` en refreshte ze allemaal in één call.
-- Gevolg voor multi-tenant users:
--   1. Auto-populate op tenant A wipet ook tenant B's cache
--   2. Massive I/O amplification bij concurrent user-tabs
--   3. Deadlock-risico bij overlapping tenant-sets in verschillende
--      volgorde tussen twee callers
--
-- Fix (Claude Agent 1 #1 + Codex I1 fix-suggestie):
--   1. Voeg p_owning_account_id uuid parameter toe (verplicht)
--   2. Valideer via basejump.has_role_on_account (tenant-authorization)
--   3. Scope DELETE + INSERT tot dat single account
--   4. Drop oude signature — geen backward-compat overload, alle
--      callers geüpdatet in dezelfde commit
-- ================================================================

drop function if exists public.refresh_mart_loonkloof(text);


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

    -- Audit (ISS-082 pattern: eigen exception block zodat audit-drift
    -- de refresh niet breekt).
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

    -- Delete oude cache voor DIT specifieke tenant-account.
    delete from public.mart_loonkloof
    where owning_account_id = p_owning_account_id;

    -- Rebuild vanuit fact-tables, gefilterd op dit account.
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
    from lonen_maand lm;

    get diagnostics v_rowcount = row_count;
    return v_rowcount;
end;
$$;

comment on function public.refresh_mart_loonkloof(uuid, text) is
    'Rebuild mart_loonkloof cache voor één tenant-account. ISS-091: '
    'p_owning_account_id verplicht met has_role_on_account check — geen '
    'cross-tenant amplification meer. Rechtsgrondslag verplicht (GDPR audit).';

revoke execute on function public.refresh_mart_loonkloof(uuid, text) from public;
grant execute on function public.refresh_mart_loonkloof(uuid, text) to authenticated;
