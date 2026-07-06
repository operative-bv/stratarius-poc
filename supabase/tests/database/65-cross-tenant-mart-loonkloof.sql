-- ================================================================
-- Cross-tenant leak regression test — mart_loonkloof + decomp_read
-- ================================================================
--
-- Learn-from-incident: op 2026-07-05 lekte mart_loonkloof cross-tenant
-- (materialized view bypasst RLS by design). Fix in commits 79b22f4
-- + 20260705180000: expliciete tenant filter + RPC guard.
--
-- Deze test lockt beide fixes vast.
--
-- ISS-084 aanteknening: setup gebeurt als postgres (voor tests.authenticate_as
-- switch de role naar authenticated). basejump.account_user rijen worden
-- handmatig ingevoegd want auth.uid()-trigger doet niks buiten user-context.
-- ================================================================

BEGIN;
create extension if not exists pgtap;

select plan(4);

------------------------------------------------------------
-- Setup ALS postgres: users, accounts, membership + team A tenant data
------------------------------------------------------------

select tests.create_supabase_user('mart_team_a_owner');
select tests.create_supabase_user('mart_team_b_owner');

-- Team A account + koppel team A owner als primary_owner
insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values (
    'aa000000-0000-0000-0000-000000000001'::uuid,
    'Mart Team A', 'mart-team-a', false,
    tests.get_supabase_uid('mart_team_a_owner')
);
insert into basejump.account_user (user_id, account_id, account_role) values (
    tests.get_supabase_uid('mart_team_a_owner'),
    'aa000000-0000-0000-0000-000000000001'::uuid,
    'owner'
);

-- Team B account + koppel team B owner
insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values (
    'bb000000-0000-0000-0000-000000000001'::uuid,
    'Mart Team B', 'mart-team-b', false,
    tests.get_supabase_uid('mart_team_b_owner')
);
insert into basejump.account_user (user_id, account_id, account_role) values (
    tests.get_supabase_uid('mart_team_b_owner'),
    'bb000000-0000-0000-0000-000000000001'::uuid,
    'owner'
);

-- Team A tenant data
insert into public.dim_legale_entiteit (
    legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id
) values (
    'aa000000-0000-0000-0000-a00000000001'::uuid,
    'aa000000-0000-0000-0000-000000000001'::uuid,
    1, 'Mart A BVBA', 'BE'
);

insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind) values (
    'aa000000-0000-0000-0000-a00000000002'::uuid,
    'aa000000-0000-0000-0000-a00000000001'::uuid,
    'Baseline A', 'baseline'
);

insert into public.dim_functie (functie_id, owning_account_id, functienaam, functieniveau) values (
    'aa000000-0000-0000-0000-a00000000003'::uuid,
    'aa000000-0000-0000-0000-000000000001'::uuid,
    'Sales A', 5
);

insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum, opleidingsniveau) values (
    'aa000000-0000-0000-0000-a00000000004'::uuid,
    'aa000000-0000-0000-0000-000000000001'::uuid,
    'm', '1985-01-01', 'hooggeschoold'
);

insert into public.dim_contract (
    contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van
) values (
    'aa000000-0000-0000-0000-a00000000005'::uuid,
    'aa000000-0000-0000-0000-a00000000004'::uuid,
    'aa000000-0000-0000-0000-a00000000001'::uuid,
    'aa000000-0000-0000-0000-a00000000003'::uuid,
    '200', 'bediende', 1.0, '2025-01-01'
);

insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values (
    'aa000000-0000-0000-0000-a00000000005'::uuid,
    '2026-06-01', 'basisloon',
    'aa000000-0000-0000-0000-a00000000002'::uuid,
    3500
);

------------------------------------------------------------
-- Refresh mart als team A (authenticated) via SECURITY DEFINER RPC
------------------------------------------------------------

select tests.authenticate_as('mart_team_a_owner');
select public.refresh_mart_loonkloof(
    'aa000000-0000-0000-0000-000000000001'::uuid,
    'pgTAP test setup'
);

------------------------------------------------------------
-- Switch naar team B → assertions
------------------------------------------------------------

select tests.authenticate_as('mart_team_b_owner');

------------------------------------------------------------
-- Sanity: Team B ziet 0 entiteiten in dim_legale_entiteit RLS'd view
-- (bewijst dat authenticate_as role-switch werkt + RLS actief is)
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_legale_entiteit),
    0,
    'team B ziet 0 entiteiten in dim_legale_entiteit (RLS sanity check)'
);

------------------------------------------------------------
-- Assertion 1: Team B ziet ZERO rijen via de app-side filter pattern
-- (loonkloof/page.tsx + oaxaca-action.ts pattern: filter mart op
-- legale_entiteit_id IN (select ... from dim_legale_entiteit) waar
-- dim_legale_entiteit RLS de subquery leeg maakt voor team B).
------------------------------------------------------------

select is(
    (
        select count(*)::int
        from public.mart_loonkloof m
        where m.legale_entiteit_id in (
            select legale_entiteit_id from public.dim_legale_entiteit
        )
    ),
    0,
    'team B ziet 0 mart_loonkloof rijen via .in(entiteitIds) — RLS op dim_legale_entiteit filtert subquery leeg (regression guard 79b22f4)'
);

------------------------------------------------------------
-- Assertion 2: mart_loonkloof_decomp_read RPC weigert team B's
-- call met team A's legale_entiteit_id (ISS-083 fix regression guard)
------------------------------------------------------------

select throws_ok(
    $$ select * from public.mart_loonkloof_decomp_read(
        'cross-tenant test attempt',
        'aa000000-0000-0000-0000-a00000000001'::uuid,
        null
    ) $$,
    '42501',
    'mart_loonkloof_decomp_read: geen toegang tot entiteit aa000000-0000-0000-0000-a00000000001',
    'decomp_read RPC weigert team B cross-tenant call (regression guard ISS-083)'
);

------------------------------------------------------------
-- Assertion 3: Team A kan wel z'n eigen entiteit querien via
-- decomp_read (positive control — RPC blokkeert alleen cross-tenant)
------------------------------------------------------------

select tests.authenticate_as('mart_team_a_owner');

select lives_ok(
    $$ select * from public.mart_loonkloof_decomp_read(
        'own-tenant test',
        'aa000000-0000-0000-0000-a00000000001'::uuid,
        null
    ) $$,
    'team A kan eigen entiteit querien via decomp_read (positive control)'
);

select * from finish();
ROLLBACK;
