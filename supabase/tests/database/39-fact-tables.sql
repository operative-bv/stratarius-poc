BEGIN;
-- T-022: fact_looncomponent + fact_prestatie + fact_wagen + fact_loonkost
-- Depends on: dim_contract (T-006), dim_looncomponent (T-011), dim_prestatiecode (T-013),
--   dim_scenario (T-014), audit_parameter_snapshot (T-021).
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration. Bij eerste run zonder migration MOET dit falen (Red). Na migration
-- run: alle 41 assertions slagen (Green).

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(41);

-- Setup: 2 team accounts + legale entiteit + contract + scenario per tenant
select tests.create_supabase_user('tenant_a_owner');
select tests.create_supabase_user('tenant_b_owner');

select tests.authenticate_as('tenant_a_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('a1111111-1111-1111-1111-111111111111', 'Tenant A', 'tenant-a', false);
insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('aaaaaaaa-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 1, 'Tenant A BVBA', 'BE');
insert into public.dim_persoon (persoon_id, geslacht, geboortedatum) values
    ('a2222222-1111-1111-1111-111111111111', 'V', '1985-01-01');
insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, pc_id, statuut, fte_breuk, geldig_van) values
    ('a3333333-1111-1111-1111-111111111111', 'a2222222-1111-1111-1111-111111111111',
     'aaaaaaaa-1111-1111-1111-111111111111', '200', 'bediende', 1.0000, '2024-01-01');
insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind) values
    ('a4444444-1111-1111-1111-111111111111', 'aaaaaaaa-1111-1111-1111-111111111111', 'Actual A', 'actual');

select tests.authenticate_as('tenant_b_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('b1111111-2222-2222-2222-222222222222', 'Tenant B', 'tenant-b', false);
insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('bbbbbbbb-2222-2222-2222-222222222222', 'b1111111-2222-2222-2222-222222222222', 1, 'Tenant B BVBA', 'BE');
insert into public.dim_persoon (persoon_id, geslacht, geboortedatum) values
    ('b2222222-2222-2222-2222-222222222222', 'M', '1985-01-01');
insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, pc_id, statuut, fte_breuk, geldig_van) values
    ('b3333333-2222-2222-2222-222222222222', 'b2222222-2222-2222-2222-222222222222',
     'bbbbbbbb-2222-2222-2222-222222222222', '200', 'bediende', 1.0000, '2024-01-01');


------------------------------------------------------------
-- Schema shape (11 assertions)
------------------------------------------------------------

select has_table('public', 'fact_looncomponent', 'fact_looncomponent table exists');
select has_table('public', 'fact_prestatie', 'fact_prestatie table exists');
select has_table('public', 'fact_wagen', 'fact_wagen table exists');
select has_table('public', 'fact_loonkost', 'fact_loonkost table exists');
select col_is_pk('public', 'fact_looncomponent', 'fact_looncomponent_id', 'fact_looncomponent PK');
select col_is_pk('public', 'fact_prestatie', 'fact_prestatie_id', 'fact_prestatie PK');
select col_is_pk('public', 'fact_wagen', 'fact_wagen_id', 'fact_wagen PK');
select col_is_pk('public', 'fact_loonkost', 'fact_loonkost_id', 'fact_loonkost PK');
select col_type_is('public', 'fact_looncomponent', 'bedrag', 'numeric(18,4)',
    'fact_looncomponent.bedrag is numeric(18,4) per Constitution v1.0.1 money precision');
select col_type_is('public', 'fact_wagen', 'co2_g_km', 'smallint',
    'fact_wagen.co2_g_km is smallint (discrete engineering unit)');
select col_type_is('public', 'fact_loonkost', 'bedrag', 'numeric(18,4)',
    'fact_loonkost.bedrag is numeric(18,4) money precision');


------------------------------------------------------------
-- NOT NULL smoke (8 assertions — symmetric per tabel)
------------------------------------------------------------

select col_not_null('public', 'fact_looncomponent', 'contract_id', 'fact_looncomponent.contract_id NOT NULL');
select col_not_null('public', 'fact_looncomponent', 'bedrag', 'fact_looncomponent.bedrag NOT NULL');
select col_not_null('public', 'fact_prestatie', 'contract_id', 'fact_prestatie.contract_id NOT NULL');
select col_not_null('public', 'fact_prestatie', 'uren', 'fact_prestatie.uren NOT NULL');
select col_not_null('public', 'fact_wagen', 'contract_id', 'fact_wagen.contract_id NOT NULL');
select col_not_null('public', 'fact_wagen', 'catalogus_waarde', 'fact_wagen.catalogus_waarde NOT NULL');
select col_not_null('public', 'fact_loonkost', 'kostenblok', 'fact_loonkost.kostenblok NOT NULL');
select col_not_null('public', 'fact_loonkost', 'scenario_id', 'fact_loonkost.scenario_id NOT NULL');


------------------------------------------------------------
-- CHECK constraints (7 assertions — maand-begin per tabel + enum/range)
-- Draai als service_role om RLS/REVOKE te bypassen en direct de CHECK te raken.
------------------------------------------------------------

select tests.clear_authentication();
set local role service_role;

-- Maand-begin CHECK per fact-tabel (4)
select throws_ok(
    $$ insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-15', 'basisloon',
               'a4444444-1111-1111-1111-111111111111', 100.0000) $$,
    '23514'
);

select throws_ok(
    $$ insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-15', 'normale_uren', 8.0000, 1.0000) $$,
    '23514'
);

select throws_ok(
    $$ insert into public.fact_wagen (contract_id, periode, catalogus_waarde, co2_g_km, brandstoftype, aanschaffingsdatum)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-15', 30000.0000, 100, 'benzine', '2023-01-01') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.fact_loonkost (contract_id, periode, kostenblok, scenario_id, bedrag, snapshot_batch_id)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-15', 'bruto',
               'a4444444-1111-1111-1111-111111111111', 100.0000, gen_random_uuid()) $$,
    '23514'
);

-- kostenblok enum CHECK
select throws_ok(
    $$ insert into public.fact_loonkost (contract_id, periode, kostenblok, scenario_id, bedrag, snapshot_batch_id)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 'random_kostenblok',
               'a4444444-1111-1111-1111-111111111111', 100.0000, gen_random_uuid()) $$,
    '23514'
);

-- brandstoftype enum CHECK
select throws_ok(
    $$ insert into public.fact_wagen (contract_id, periode, catalogus_waarde, co2_g_km, brandstoftype, aanschaffingsdatum)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 30000.0000, 100, 'onbekend_type', '2023-01-01') $$,
    '23514'
);

-- CO2 range CHECK
select throws_ok(
    $$ insert into public.fact_wagen (contract_id, periode, catalogus_waarde, co2_g_km, brandstoftype, aanschaffingsdatum)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 30000.0000, 501, 'benzine', '2023-01-01') $$,
    '23514'
);

reset role;


------------------------------------------------------------
-- RLS tenant-scoping (8 assertions)
--   3 own-tenant lives_ok INSERT + 3 cross-tenant read=0 + 2 cross-tenant negative INSERT
------------------------------------------------------------

-- Own-tenant INSERT lives_ok (3)
select tests.authenticate_as('tenant_a_owner');

select lives_ok(
    $$ insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 'basisloon',
               'a4444444-1111-1111-1111-111111111111', 4000.0000) $$,
    'tenant A owner INSERT eigen fact_looncomponent lives_ok'
);

select lives_ok(
    $$ insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 'normale_uren', 164.0000, 21.0000) $$,
    'tenant A owner INSERT eigen fact_prestatie lives_ok'
);

select lives_ok(
    $$ insert into public.fact_wagen (contract_id, periode, catalogus_waarde, co2_g_km, brandstoftype, aanschaffingsdatum)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 30000.0000, 100, 'benzine', '2023-01-01') $$,
    'tenant A owner INSERT eigen fact_wagen lives_ok'
);

-- Cross-tenant read=0 (3)
select tests.authenticate_as('tenant_b_owner');

select is(
    (select count(*)::int from public.fact_looncomponent),
    0,
    'tenant B sees 0 fact_looncomponent van tenant A (RLS tenant-scoping)'
);

select is(
    (select count(*)::int from public.fact_prestatie),
    0,
    'tenant B sees 0 fact_prestatie van tenant A (RLS tenant-scoping)'
);

select is(
    (select count(*)::int from public.fact_wagen),
    0,
    'tenant B sees 0 fact_wagen van tenant A (RLS tenant-scoping)'
);

-- Cross-tenant negative INSERT (2) — Tenant B probeert INSERT met contract van Tenant A
select throws_ok(
    $$ insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag)
       values ('a3333333-1111-1111-1111-111111111111', '2024-04-01', 'basisloon',
               'a4444444-1111-1111-1111-111111111111', 4000.0000) $$,
    '42501'
);

select throws_ok(
    $$ insert into public.fact_wagen (contract_id, periode, catalogus_waarde, co2_g_km, brandstoftype, aanschaffingsdatum)
       values ('a3333333-1111-1111-1111-111111111111', '2024-04-01', 30000.0000, 100, 'benzine', '2023-01-01') $$,
    '42501'
);


------------------------------------------------------------
-- AFGELEID-invariant op fact_loonkost (3 assertions)
------------------------------------------------------------

select tests.authenticate_as('tenant_a_owner');

-- Authenticated INSERT → REVOKED (42501)
select throws_ok(
    $$ insert into public.fact_loonkost (contract_id, periode, kostenblok, scenario_id, bedrag, snapshot_batch_id)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 'bruto',
               'a4444444-1111-1111-1111-111111111111', 4000.0000, gen_random_uuid()) $$,
    '42501'
);

-- Authenticated UPDATE → REVOKED (42501)
-- Zorgen dat er niks staat om te updaten kan; syntactisch valide UPDATE moet 42501 geven vóór row-check.
select throws_ok(
    $$ update public.fact_loonkost set bedrag = 5000.0000 where kostenblok = 'bruto' $$,
    '42501'
);

-- Service_role INSERT → lives_ok (bypass REVOKE)
select tests.clear_authentication();
set local role service_role;

select lives_ok(
    $$ insert into public.fact_loonkost (contract_id, periode, kostenblok, scenario_id, bedrag, snapshot_batch_id)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 'bruto',
               'a4444444-1111-1111-1111-111111111111', 4000.0000, gen_random_uuid()) $$,
    'service_role INSERT op fact_loonkost lives_ok (AFGELEID-invariant respecteert cascade-schrijfroute)'
);


------------------------------------------------------------
-- Unieke sleutels (2 assertions)
--   Draai als service_role om RLS/REVOKE te bypassen en direct unique-CHECK te raken.
------------------------------------------------------------

select throws_ok(
    $$ insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 'basisloon',
               'a4444444-1111-1111-1111-111111111111', 5000.0000) $$,
    '23505'
);

select throws_ok(
    $$ insert into public.fact_loonkost (contract_id, periode, kostenblok, scenario_id, bedrag, snapshot_batch_id)
       values ('a3333333-1111-1111-1111-111111111111', '2024-03-01', 'bruto',
               'a4444444-1111-1111-1111-111111111111', 4500.0000, gen_random_uuid()) $$,
    '23505'
);


------------------------------------------------------------
-- FK integrity (2 assertions)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag)
       values ('99999999-9999-9999-9999-999999999999', '2024-04-01', 'basisloon',
               'a4444444-1111-1111-1111-111111111111', 4000.0000) $$,
    '23503'
);

select throws_ok(
    $$ insert into public.fact_loonkost (contract_id, periode, kostenblok, scenario_id, bedrag, snapshot_batch_id)
       values ('a3333333-1111-1111-1111-111111111111', '2024-04-01', 'bruto',
               '99999999-9999-9999-9999-999999999999', 4000.0000, gen_random_uuid()) $$,
    '23503'
);

reset role;


select * from finish();
ROLLBACK;
