-- ================================================================
-- ISS-103: Multi-membership regression tests
-- ================================================================
--
-- Codex ronde 2 S1. Test 65 dekt scenario "user zonder toegang tot
-- andere tenant" — bewijst dat RLS werkt bij zero-access. Deze test
-- dekt het andere spectrum: user MET toegang tot beide tenants, om
-- te bewijzen dat de fixes uit ISS-088 (scenario RPC tenant check) +
-- ISS-091 (refresh_mart_loonkloof single-tenant scope) + ISS-098
-- (accountSlug filter) daadwerkelijk voorkomen dat operatie op A per
-- ongeluk tenant B raakt.
--
-- ISS-099 REVOKE op mart_loonkloof: read_mart_loonkloof RPC is
-- canonieke read-path. Test dat read_mart_loonkloof met p_owning_account
-- van tenant A ALLEEN tenant A rijen returned zelfs als caller ook
-- toegang heeft tot tenant B.
-- ================================================================

BEGIN;
create extension if not exists pgtap;

select plan(4);

------------------------------------------------------------
-- Setup ALS postgres: één user met membership op BEIDE tenants
------------------------------------------------------------

select tests.create_supabase_user('multi_owner');

-- Tenant A
insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values (
    'cc000000-0000-0000-0000-000000000001'::uuid,
    'Multi A', 'multi-a', false,
    tests.get_supabase_uid('multi_owner')
);
insert into basejump.account_user (user_id, account_id, account_role) values (
    tests.get_supabase_uid('multi_owner'),
    'cc000000-0000-0000-0000-000000000001'::uuid,
    'owner'
);

-- Tenant B — zelfde user
insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values (
    'dd000000-0000-0000-0000-000000000001'::uuid,
    'Multi B', 'multi-b', false,
    tests.get_supabase_uid('multi_owner')
);
insert into basejump.account_user (user_id, account_id, account_role) values (
    tests.get_supabase_uid('multi_owner'),
    'dd000000-0000-0000-0000-000000000001'::uuid,
    'owner'
);

-- Tenant A data
insert into public.dim_legale_entiteit (
    legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id
) values (
    'cc000000-0000-0000-0000-a00000000001'::uuid,
    'cc000000-0000-0000-0000-000000000001'::uuid,
    1, 'Multi A BVBA', 'BE'
);
insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind) values (
    'cc000000-0000-0000-0000-a00000000002'::uuid,
    'cc000000-0000-0000-0000-a00000000001'::uuid,
    'Baseline A', 'baseline'
);
insert into public.dim_functie (functie_id, owning_account_id, functienaam, functieniveau) values (
    'cc000000-0000-0000-0000-a00000000003'::uuid,
    'cc000000-0000-0000-0000-000000000001'::uuid,
    'Sales A', 5
);
insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum, opleidingsniveau) values (
    'cc000000-0000-0000-0000-a00000000004'::uuid,
    'cc000000-0000-0000-0000-000000000001'::uuid,
    'm', '1985-01-01', 'hooggeschoold'
);
insert into public.dim_contract (
    contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van
) values (
    'cc000000-0000-0000-0000-a00000000005'::uuid,
    'cc000000-0000-0000-0000-a00000000004'::uuid,
    'cc000000-0000-0000-0000-a00000000001'::uuid,
    'cc000000-0000-0000-0000-a00000000003'::uuid,
    '200', 'bediende', 1.0, '2025-01-01'
);
insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values (
    'cc000000-0000-0000-0000-a00000000005'::uuid,
    '2026-06-01', 'basisloon',
    'cc000000-0000-0000-0000-a00000000002'::uuid,
    3500
);

-- Tenant B data — één persoon, andere geslacht (om te bewijzen dat B-data niet in A-read verschijnt)
insert into public.dim_legale_entiteit (
    legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id
) values (
    'dd000000-0000-0000-0000-a00000000001'::uuid,
    'dd000000-0000-0000-0000-000000000001'::uuid,
    2, 'Multi B BVBA', 'BE'
);
insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind) values (
    'dd000000-0000-0000-0000-a00000000002'::uuid,
    'dd000000-0000-0000-0000-a00000000001'::uuid,
    'Baseline B', 'baseline'
);
insert into public.dim_functie (functie_id, owning_account_id, functienaam, functieniveau) values (
    'dd000000-0000-0000-0000-a00000000003'::uuid,
    'dd000000-0000-0000-0000-000000000001'::uuid,
    'Sales B', 5
);
insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum, opleidingsniveau) values (
    'dd000000-0000-0000-0000-a00000000004'::uuid,
    'dd000000-0000-0000-0000-000000000001'::uuid,
    'v', '1990-01-01', 'hooggeschoold'
);
insert into public.dim_contract (
    contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van
) values (
    'dd000000-0000-0000-0000-a00000000005'::uuid,
    'dd000000-0000-0000-0000-a00000000004'::uuid,
    'dd000000-0000-0000-0000-a00000000001'::uuid,
    'dd000000-0000-0000-0000-a00000000003'::uuid,
    '200', 'bediende', 1.0, '2025-01-01'
);
insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values (
    'dd000000-0000-0000-0000-a00000000005'::uuid,
    '2026-06-01', 'basisloon',
    'dd000000-0000-0000-0000-a00000000002'::uuid,
    3500
);

------------------------------------------------------------
-- Switch naar authenticated als multi_owner + populate BEIDE marts
------------------------------------------------------------

select tests.authenticate_as('multi_owner');

-- Refresh voor tenant A
select public.refresh_mart_loonkloof(
    'cc000000-0000-0000-0000-000000000001'::uuid,
    'multi-tenant test setup A'
);
-- Refresh voor tenant B
select public.refresh_mart_loonkloof(
    'dd000000-0000-0000-0000-000000000001'::uuid,
    'multi-tenant test setup B'
);

------------------------------------------------------------
-- Assertion 1: read_mart_loonkloof(tenant A) toont ALLEEN A geslacht=m
------------------------------------------------------------

select is(
    (
        select array_agg(distinct geslacht order by geslacht)::text
        from public.read_mart_loonkloof(
            'cc000000-0000-0000-0000-000000000001'::uuid,
            'test A read',
            '2026-06-30'::date,
            null
        )
    ),
    '{m}',
    'ISS-098+099: read_mart_loonkloof(tenant A) returned alleen tenant A rijen (geslacht=m), niet tenant B (geslacht=v)'
);

------------------------------------------------------------
-- Assertion 2: read_mart_loonkloof(tenant B) toont ALLEEN B geslacht=v
------------------------------------------------------------

select is(
    (
        select array_agg(distinct geslacht order by geslacht)::text
        from public.read_mart_loonkloof(
            'dd000000-0000-0000-0000-000000000001'::uuid,
            'test B read',
            '2026-06-30'::date,
            null
        )
    ),
    '{v}',
    'ISS-098+099: read_mart_loonkloof(tenant B) returned alleen tenant B rijen (geslacht=v), niet tenant A (geslacht=m)'
);

------------------------------------------------------------
-- Assertion 3: create_what_if_scenario weigert cross-tenant baseline
-- (tenant A entiteit + tenant B baseline scenario = fout)
------------------------------------------------------------

select throws_ok(
    $$ select public.create_what_if_scenario(
        'cc000000-0000-0000-0000-a00000000001'::uuid,
        'cross-tenant attempt',
        'dd000000-0000-0000-0000-a00000000002'::uuid,
        '2026-06-01'::date,
        'pct_increase',
        5.0,
        null
    ) $$,
    '42501',
    null,
    'ISS-088: create_what_if_scenario weigert baseline scenario van andere tenant zelfs bij multi-membership'
);

------------------------------------------------------------
-- Assertion 4: clear_tenant_populatie werkt alleen op opgegeven entiteit
-- Multi-owner die A clear'd raakt B niet.
------------------------------------------------------------

-- Baseline count vóór clear
create temp table _iss103_pre_counts as
select
    (select count(*)::int from public.dim_contract where legale_entiteit_id = 'cc000000-0000-0000-0000-a00000000001'::uuid) as a_contracts,
    (select count(*)::int from public.dim_contract where legale_entiteit_id = 'dd000000-0000-0000-0000-a00000000001'::uuid) as b_contracts;

-- Clear tenant A
select public.clear_tenant_populatie('cc000000-0000-0000-0000-a00000000001'::uuid);

-- Post-clear: A moet 0 contracten hebben, B moet ongewijzigd zijn.
select is(
    (
        select
            (select count(*)::int from public.dim_contract where legale_entiteit_id = 'cc000000-0000-0000-0000-a00000000001'::uuid) = 0
            and
            (select count(*)::int from public.dim_contract where legale_entiteit_id = 'dd000000-0000-0000-0000-a00000000001'::uuid) = (select b_contracts from _iss103_pre_counts)
    ),
    true,
    'ISS-098: clear_tenant_populatie(A) wist A-contracten leeg, tenant B contracten ongewijzigd (multi-membership isolation)'
);

select * from finish();
ROLLBACK;
