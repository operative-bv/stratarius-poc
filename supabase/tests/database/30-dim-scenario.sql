BEGIN;
create extension if not exists pgtap;

select plan(13);

-- Setup: two team accounts, each with a legale entiteit.
select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

select tests.authenticate_as('team_a_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('11111111-1111-1111-1111-111111111111', 'Team A', 'team-a', false);

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('aaaaaaaa-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 1, 'Team A BVBA', 'BE');

select tests.authenticate_as('team_b_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('22222222-2222-2222-2222-222222222222', 'Team B', 'team-b', false);

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('aaaaaaaa-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 1, 'Team B BVBA', 'BE');


------------------------------------------------------------
-- Schema shape (4 assertions)
------------------------------------------------------------

select has_table('public', 'dim_scenario', 'dim_scenario table exists');
select col_is_pk('public', 'dim_scenario', 'scenario_id', 'scenario_id is PK');
select col_is_fk('public', 'dim_scenario', 'legale_entiteit_id', 'legale_entiteit_id is FK');
select col_not_null('public', 'dim_scenario', 'kind', 'kind NOT NULL');


------------------------------------------------------------
-- Team A owner inserts scenarios (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select lives_ok(
    $$ insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind, geldig_van, geldig_tot)
       values ('bbbbbbbb-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               'Actual 2024', 'actual', '2024-01-01', '2025-01-01') $$,
    'team A owner can insert an actual scenario'
);


------------------------------------------------------------
-- kind CHECK enforcement (1 assertion)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_scenario (legale_entiteit_id, naam, kind)
       values ('aaaaaaaa-1111-1111-1111-111111111111', 'Bad', 'invalid_kind') $$,
    '23514'
);


------------------------------------------------------------
-- Effective-dating CHECK: geldig_van >= geldig_tot rejected (1 assertion)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_scenario (legale_entiteit_id, naam, kind, geldig_van, geldig_tot)
       values ('aaaaaaaa-1111-1111-1111-111111111111', 'Bad dates', 'what_if', '2024-06-01', '2024-01-01') $$,
    '23514'
);


------------------------------------------------------------
-- Cross-tenant filter: Team B sees 0 rows (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.dim_scenario),
    0,
    'Team B sees 0 dim_scenario rows (RLS filters via transitive tenant)'
);


------------------------------------------------------------
-- Cross-tenant INSERT block via WITH CHECK (1 assertion)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_scenario (legale_entiteit_id, naam, kind)
       values ('aaaaaaaa-1111-1111-1111-111111111111', 'Hijack', 'what_if') $$,
    '42501'
);


------------------------------------------------------------
-- FK RESTRICT: cannot delete legale_entiteit met scenario hanging.
-- Runs as service_role to bypass RLS/REVOKE so FK RESTRICT genuinely fires.
------------------------------------------------------------

select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ delete from public.dim_legale_entiteit where legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111' $$,
    '23503'
);

reset role;


------------------------------------------------------------
-- Multiple scenarios per legale entiteit (2 assertions — proves the
-- "meerdere scenario's per contract × periode" use case)
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select lives_ok(
    $$ insert into public.dim_scenario (legale_entiteit_id, naam, kind, beschrijving)
       values ('aaaaaaaa-1111-1111-1111-111111111111',
               'Voorstel indexatie +2%', 'what_if',
               'Simulatie: indexcoëfficient +2% ipv +1.5%') $$,
    'team A owner can add a what_if scenario to same legale entiteit'
);

select is(
    (select count(*)::int from public.dim_scenario where legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'),
    2,
    'Team A legale entiteit heeft 2 scenarios (actual + what_if)'
);


------------------------------------------------------------
-- All 4 valid kinds accepted (1 assertion — 3rd + 4th kind samples)
------------------------------------------------------------

select lives_ok(
    $$ insert into public.dim_scenario (legale_entiteit_id, naam, kind)
       values ('aaaaaaaa-1111-1111-1111-111111111111', 'Forecast 2025', 'forecast'),
              ('aaaaaaaa-1111-1111-1111-111111111111', 'Baseline oorspronkelijke begroting', 'baseline') $$,
    'forecast + baseline kind values accepted'
);


select * from finish();
ROLLBACK;
