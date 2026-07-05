-- ================================================================
-- Materialize cascade: mart_populatie_loonkost cache table
-- ================================================================
--
-- Elke populatie page-load doet nu een `cascade_populatie_snapshot` live-call
-- (2-4s voor 1000 contracten). Deze migratie voegt een persistent cache toe
-- zodat page loads onder 200ms zijn, met expliciete refresh-actie voor de user.
--
-- Architectuur:
-- - Table `mart_populatie_loonkost` — denormalized cascade output per contract
--   × scenario × periode. `owning_account_id` op de row voor RLS-scope.
-- - RPC `refresh_populatie_loonkost_cache` — SECURITY DEFINER wrapper: tenant
--   check + delete-existing + insert-nieuwe via cascade_populatie_snapshot.
-- - RLS policy: has_role_on_account op owning_account_id.
--
-- Cascade_populatie_snapshot blijft de source-of-truth voor live compute
-- (bijv. simulator, of dashboard-preview zonder refresh). Deze cache is
-- opt-in via refresh RPC.
-- ================================================================

create table public.mart_populatie_loonkost (
    contract_id             uuid                     not null,
    persoon_id              uuid                     not null,
    legale_entiteit_id      uuid                     not null,
    owning_account_id       uuid                     not null references basejump.accounts(id) on delete cascade,
    scenario_id             uuid                     not null,
    periode                 date                     not null,
    pc_id                   text                     not null,
    status                  text                     not null,
    werkgeverscategorie     smallint                 not null,
    functie_id              uuid                     not null,
    functienaam             text                     not null,
    mu                      numeric(6, 4)            not null,
    bruto                   numeric(18, 4)           not null,
    stap2_basis_rsz         numeric(18, 4)           not null,
    stap3_vermindering      numeric(18, 4)           not null,
    stap4_doelgroep         numeric(18, 4)           not null,
    stap5_bijzondere        numeric(18, 4)           not null,
    stap6_vakantiegeld      numeric(18, 4)           not null,
    stap7_extralegaal       numeric(18, 4)           not null,
    stap8_wagen             numeric(18, 4)           not null,
    stap9_arbeidsongevallen numeric(18, 4)           not null,
    totaal_patronale_kost   numeric(18, 4)           not null,
    tco                     numeric(18, 4)           not null,
    refreshed_at            timestamptz              not null default now(),
    primary key (contract_id, scenario_id, periode)
);

create index mart_populatie_loonkost_tenant_scenario_periode_idx
    on public.mart_populatie_loonkost (owning_account_id, scenario_id, periode);

comment on table public.mart_populatie_loonkost is
    'Cascade output cache per contract × scenario × periode. Populated via refresh_populatie_loonkost_cache RPC. Elke row heeft owning_account_id voor RLS-scope; refreshed_at voor freshness UI.';


-- ================================================================
-- RLS: tenant-scope via has_role_on_account
-- ================================================================

alter table public.mart_populatie_loonkost enable row level security;

create policy mart_populatie_loonkost_tenant_read on public.mart_populatie_loonkost
    for select
    using (basejump.has_role_on_account(owning_account_id));

-- Geen INSERT/UPDATE/DELETE grants voor authenticated — writes gaan enkel
-- via SECURITY DEFINER refresh RPC (die zelf tenant check doet).

grant select on public.mart_populatie_loonkost to authenticated;


-- ================================================================
-- Refresh RPC — SECURITY DEFINER met tenant check + audit
-- ================================================================

-- Refresh gebruikt GEEN filters — cache is unfiltered per tenant × scenario × periode.
-- Filters worden client-side toegepast op leestijd (contract-count is beperkt tot
-- tenant's populatie, dus geen performance issue).
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

    -- Tenant check op scenario_id (bypasst RLS via DEFINER).
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

    -- Audit log (matcht ISS-082 pattern: eigen exception block).
    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator,
            'refresh_populatie_loonkost_cache',
            array['persoon_id', 'geslacht', 'opleidingsniveau'],
            'HR loonkost cache refresh voor scenario ' || p_scenario_id::text,
            0,
            'read'
        );
    exception
        when others then
            raise warning 'refresh_populatie_loonkost_cache: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    -- Delete existing rows voor deze tenant × scenario × periode combinatie.
    delete from public.mart_populatie_loonkost
    where owning_account_id = v_scenario_account
      and scenario_id = p_scenario_id
      and periode = p_periode;

    -- Insert nieuwe cache via cascade_populatie_snapshot output.
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
    join public.dim_contract c on c.contract_id = s.contract_id;

    get diagnostics v_rowcount = row_count;
    return v_rowcount;
end;
$$;

comment on function public.refresh_populatie_loonkost_cache(date, uuid) is
    'Rebuild mart_populatie_loonkost cache voor caller''s tenant × scenario × periode (unfiltered). Tenant check via has_role_on_account + gdpr_access_log audit. Returns rowcount inserted. Filters worden client-side toegepast.';

revoke execute on function public.refresh_populatie_loonkost_cache(date, uuid) from public;
grant execute on function public.refresh_populatie_loonkost_cache(date, uuid) to authenticated;
