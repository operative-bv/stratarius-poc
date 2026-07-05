-- ================================================================
-- Refactor: mart_loonkloof materialized view → gewone tabel + RLS
-- ================================================================
--
-- ISS-077 achtergrond: mart_loonkloof was een materialized view die RLS
-- bypasste. We hebben dat gepatched met app-side .in("legale_entiteit_id",
-- entiteitIds) filter — policy-based veilig, niet architectural.
--
-- Deze migratie matcht het mart_populatie_loonkost patroon:
-- 1. Tabel met owning_account_id kolom voor RLS
-- 2. RLS policy: has_role_on_account(owning_account_id)
-- 3. Refresh RPC per-tenant (delete + insert) ipv REFRESH MATERIALIZED VIEW
-- 4. Auto-invalidate via mutatie-RPCs (bulk_import, clear_populatie)
-- 5. Views + read RPCs updaten om nieuwe tabel te gebruiken
--
-- Impact op app-code (aparte commit):
-- - loonkloof/page.tsx: .in("legale_entiteit_id", entiteitIds) filter kan
--   weg (RLS doet het werk)
-- - oaxaca-action.ts: idem
-- - "Refresh mart" button in loonkloof UI: kan verdwijnen (auto-invalidate)
-- ================================================================

-- ================================================================
-- 1. Drop bestaande objects in juiste volgorde (dependencies)
-- ================================================================

drop function if exists public.mart_loonkloof_decomp_read(text, uuid, text) cascade;
drop view if exists public.mart_loonkloof_decomp cascade;
drop function if exists public.refresh_mart_loonkloof(text) cascade;
drop materialized view if exists public.mart_loonkloof cascade;


-- ================================================================
-- 2. Nieuwe mart_loonkloof tabel met owning_account_id + RLS
-- ================================================================

create table public.mart_loonkloof (
    persoon_id            uuid                     not null,
    legale_entiteit_id    uuid                     not null,
    owning_account_id     uuid                     not null references basejump.accounts(id) on delete cascade,
    referentiedatum       date                     not null,
    kwartaal              text                     not null,
    uurloon_bruto         numeric                  not null,
    basis_vte             numeric(18, 4)           not null,
    variabele_vte         numeric(18, 4)           not null,
    geslacht              text                     not null,
    functieniveau         smallint                 not null,
    ancienniteit_jaren    numeric(6, 2)            not null,
    refreshed_at          timestamptz              not null default now(),
    primary key (persoon_id, referentiedatum)
);

create index mart_loonkloof_tenant_idx
    on public.mart_loonkloof (owning_account_id);
create index mart_loonkloof_entiteit_idx
    on public.mart_loonkloof (legale_entiteit_id);

comment on table public.mart_loonkloof is
    'Loonkloof-mart per persoon × kwartaal. Gewone tabel met per-row owning_account_id voor RLS. Kwartaal-eindes 2024-Q1 t/m 2026-Q4. Refresh via refresh_mart_loonkloof RPC (per-tenant).';


-- ================================================================
-- 3. RLS: tenant-scope via has_role_on_account
-- ================================================================

alter table public.mart_loonkloof enable row level security;

create policy mart_loonkloof_tenant_read on public.mart_loonkloof
    for select
    using (basejump.has_role_on_account(owning_account_id));

grant select on public.mart_loonkloof to authenticated;
-- INSERT/UPDATE/DELETE alleen via refresh RPC (SECURITY DEFINER).


-- ================================================================
-- 4. Refresh RPC: per-tenant recompute
-- ================================================================

create or replace function public.refresh_mart_loonkloof(
    p_rechtsgrondslag text
)
    returns integer
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator          uuid;
    v_tenant_account_ids uuid[];
    v_rowcount           integer;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'refresh_mart_loonkloof: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'refresh_mart_loonkloof: p_rechtsgrondslag verplicht (GDPR audit)'
            using errcode = '22023';
    end if;

    -- Bepaal caller's tenant account_ids (via account_user memberships).
    select array_agg(account_id) into v_tenant_account_ids
    from basejump.account_user
    where user_id = v_initiator;

    if v_tenant_account_ids is null or array_length(v_tenant_account_ids, 1) = 0 then
        return 0;
    end if;

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

    -- Delete oude cache voor caller's tenants
    delete from public.mart_loonkloof
    where owning_account_id = any(v_tenant_account_ids);

    -- Insert nieuwe cache via de originele mart_loonkloof compute query,
    -- gefilterd op caller's tenants.
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
          and le.owning_account_id = any(v_tenant_account_ids)
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

comment on function public.refresh_mart_loonkloof(text) is
    'Rebuild mart_loonkloof cache voor caller''s tenants. Vervangt REFRESH MATERIALIZED VIEW patroon met per-tenant delete + insert. Rechtsgrondslag verplicht (GDPR audit).';

revoke execute on function public.refresh_mart_loonkloof(text) from public;
grant execute on function public.refresh_mart_loonkloof(text) to authenticated;


-- ================================================================
-- 5. mart_loonkloof_decomp view opnieuw (nu erft RLS van mart_loonkloof tabel)
-- ================================================================

create or replace view public.mart_loonkloof_decomp as
with pop as (
    select
        m.legale_entiteit_id,
        m.referentiedatum,
        m.kwartaal,
        m.persoon_id,
        m.geslacht,
        m.functieniveau,
        m.uurloon_bruto,
        m.ancienniteit_jaren,
        case
            when m.ancienniteit_jaren < 2 then 'junior'
            when m.ancienniteit_jaren < 5 then 'medior'
            else 'senior'
        end as ancienniteit_bucket,
        p.opleidingsniveau
    from public.mart_loonkloof m
    join public.dim_persoon p on p.persoon_id = m.persoon_id
),
stratum_stats as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        functieniveau, opleidingsniveau, ancienniteit_bucket, geslacht,
        avg(uurloon_bruto) as avg_uurloon,
        count(*)::int as n,
        coalesce(var_samp(uurloon_bruto), 0) as var_uurloon
    from pop
    group by legale_entiteit_id, referentiedatum, kwartaal,
             functieniveau, opleidingsniveau, ancienniteit_bucket, geslacht
),
per_periode as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        avg(uurloon_bruto) filter (where geslacht = 'm') as gem_uurloon_m,
        avg(uurloon_bruto) filter (where geslacht = 'v') as gem_uurloon_v,
        count(*) filter (where geslacht = 'm')::int as n_m,
        count(*) filter (where geslacht = 'v')::int as n_v,
        coalesce(var_samp(uurloon_bruto) filter (where geslacht = 'm'), 0) as var_m,
        coalesce(var_samp(uurloon_bruto) filter (where geslacht = 'v'), 0) as var_v
    from pop
    group by legale_entiteit_id, referentiedatum, kwartaal
),
strata_match as (
    select
        s_m.legale_entiteit_id, s_m.referentiedatum, s_m.kwartaal,
        (s_m.avg_uurloon - s_v.avg_uurloon) as stratum_gap,
        (s_m.n + s_v.n) as stratum_weight
    from stratum_stats s_m
    join stratum_stats s_v
        using (legale_entiteit_id, referentiedatum, kwartaal,
               functieniveau, opleidingsniveau, ancienniteit_bucket)
    where s_m.geslacht = 'm' and s_v.geslacht = 'v'
),
controlled as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        sum(stratum_gap * stratum_weight) / nullif(sum(stratum_weight), 0) as residual_gap,
        sum(stratum_weight)::int as matched_pop_size
    from strata_match
    group by legale_entiteit_id, referentiedatum, kwartaal
)
select
    p.legale_entiteit_id,
    p.referentiedatum,
    p.kwartaal,
    p.n_m,
    p.n_v,
    round(p.gem_uurloon_m::numeric, 4) as gem_uurloon_m,
    round(p.gem_uurloon_v::numeric, 4) as gem_uurloon_v,
    round((p.gem_uurloon_m - p.gem_uurloon_v)::numeric, 4) as raw_gap,
    round(coalesce(c.residual_gap, 0)::numeric, 4) as residual_gap,
    round(((p.gem_uurloon_m - p.gem_uurloon_v) - coalesce(c.residual_gap, 0))::numeric, 4) as endowment_gap,
    round(
        (1.96 * sqrt(
            case when p.n_m > 0 then p.var_m / p.n_m else 0 end +
            case when p.n_v > 0 then p.var_v / p.n_v else 0 end
        ))::numeric,
        4
    ) as raw_gap_ci95_halfwidth,
    coalesce(c.matched_pop_size, 0) as matched_stratum_pop
from per_periode p
left join controlled c using (legale_entiteit_id, referentiedatum, kwartaal);


-- ================================================================
-- 6. mart_loonkloof_decomp_read RPC (behouden dezelfde signatuur voor app-compat)
-- ================================================================
-- Nu de view erft RLS van mart_loonkloof, is de expliciete tenant check in de
-- RPC verminderd nodig maar we behouden hem voor extra defensive layer + audit.

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
    end if;

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
            0,
            'read'
        );
    exception
        when others then
            raise warning 'mart_loonkloof_decomp_read: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    -- RLS op mart_loonkloof filtert nu de tenant-scope. view is INVOKER (default),
    -- dus draait als caller — SECURITY DEFINER hier op de RPC elevated dat naar postgres
    -- die BYPASSRLS heeft. We moeten dus expliciet filteren op v_owning_account of
    -- via has_role_on_account op de leg_ent joins in de view.
    -- Pragmatisch: filter output op basis van p_legale_entiteit_id + tenant check hierboven.
    return query
        select d.*
        from public.mart_loonkloof_decomp d
        where (
            (p_legale_entiteit_id is not null and d.legale_entiteit_id = p_legale_entiteit_id)
            or (
                p_legale_entiteit_id is null
                and d.legale_entiteit_id in (
                    select le.legale_entiteit_id from public.dim_legale_entiteit le
                    where basejump.has_role_on_account(le.owning_account_id)
                )
            )
        )
        and (p_kwartaal is null or d.kwartaal = p_kwartaal);
end;
$$;

comment on function public.mart_loonkloof_decomp_read(text, uuid, text) is
    'Rechtsgrondslag-gated read op mart_loonkloof_decomp. RLS op mart_loonkloof tabel + expliciete tenant check op p_legale_entiteit_id + audit-insert (ISS-082 pattern).';

revoke execute on function public.mart_loonkloof_decomp_read(text, uuid, text) from public;
grant execute on function public.mart_loonkloof_decomp_read(text, uuid, text) to authenticated;


-- ================================================================
-- 7. Auto-invalidate mart_loonkloof cache bij mutatie-RPCs
--    (bovenop mart_populatie_loonkost invalidate uit 20260706010000)
-- ================================================================

-- bulk_import_populatie: al herschreven in 20260706010000, hier alleen
-- de mart_loonkloof delete toevoegen via CREATE OR REPLACE.
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
            naam text, geslacht text, geboortedatum date,
            opleidingsniveau text, team text, status text,
            pc text, bruto numeric
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
                v_persoon_id, p_legale_entiteit_id, v_functie_id,
                coalesce(v_row.pc, case when v_row.status = 'arbeider' then '124' else '200' end),
                coalesce(v_row.status, 'bediende'),
                1.0, p_geldig_van
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
                v_errors := v_errors || (coalesce(v_row.naam, '?') || ' [' || v_sqlstate || ']: ' || v_sqlerrm);
                v_skipped := v_skipped + 1;
                if v_sqlstate ~ '^(53|57|XX)' then raise; end if;
        end;
    end loop;

    -- Cache invalidate: mart_populatie_loonkost + mart_loonkloof beide stale.
    delete from public.mart_populatie_loonkost where owning_account_id = v_owning_account;
    delete from public.mart_loonkloof where owning_account_id = v_owning_account;

    return query select v_created, v_skipped, v_errors;
end;
$$;


-- clear_tenant_populatie: idem, mart_loonkloof delete toevoegen.
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

    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator, 'clear_tenant_populatie',
            array['contract_id', 'persoon_id'],
            'HR data cleanup — user request', 0, 'delete'
        );
    exception when others then
        raise warning 'clear_tenant_populatie: audit log insert faalde: [%] %', SQLSTATE, SQLERRM;
    end;

    -- Cache clears first
    delete from public.mart_populatie_loonkost where owning_account_id = v_owning_account;
    delete from public.mart_loonkloof where owning_account_id = v_owning_account;

    -- fact_prestatie, fact_wagen, fact_looncomponent
    delete from public.fact_prestatie where contract_id in (
        select contract_id from public.dim_contract where legale_entiteit_id = p_legale_entiteit_id
    );
    delete from public.fact_wagen where contract_id in (
        select contract_id from public.dim_contract where legale_entiteit_id = p_legale_entiteit_id
    );
    delete from public.fact_looncomponent where contract_id in (
        select contract_id from public.dim_contract where legale_entiteit_id = p_legale_entiteit_id
    );

    with deleted as (
        delete from public.dim_contract where legale_entiteit_id = p_legale_entiteit_id
        returning persoon_id
    )
    select count(*) into v_deleted_contracten from deleted;

    with deleted as (
        delete from public.dim_persoon p
        where p.owning_account_id = v_owning_account
          and not exists (select 1 from public.dim_contract c where c.persoon_id = p.persoon_id)
        returning p.persoon_id
    )
    select count(*) into v_deleted_personen from deleted;

    return query select v_deleted_contracten, v_deleted_personen;
end;
$$;
