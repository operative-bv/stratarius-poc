BEGIN;
create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(20);

-- Two team owners, each creates a team account.
select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

select tests.authenticate_as('team_a_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('11111111-1111-1111-1111-111111111111', 'Team A', 'team-a', false);

select tests.authenticate_as('team_b_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('22222222-2222-2222-2222-222222222222', 'Team B', 'team-b', false);

------------------------------------------------------------
-- Schema shape (7 assertions)
------------------------------------------------------------

select has_table('public', 'dim_land', 'dim_land table exists');
select has_table('public', 'dim_legale_entiteit', 'dim_legale_entiteit table exists');
select col_is_pk('public', 'dim_land', 'land_id', 'dim_land.land_id is PK');
select col_is_pk('public', 'dim_legale_entiteit', 'legale_entiteit_id', 'dim_legale_entiteit.legale_entiteit_id is PK');
select col_is_fk('public', 'dim_legale_entiteit', 'basejump_account_id', 'basejump_account_id is FK');
select col_is_fk('public', 'dim_legale_entiteit', 'land_id', 'land_id is FK');
select col_type_is('public', 'dim_legale_entiteit', 'werkgeverscategorie', 'smallint', 'werkgeverscategorie is smallint');

------------------------------------------------------------
-- dim_land seed (2 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_land),
    5,
    'seed created 5 countries'
);

select is(
    (select name from public.dim_land where land_id = 'BE'),
    'België',
    'BE seed name correct'
);

------------------------------------------------------------
-- dim_land global read (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select is(
    (select count(*)::int from public.dim_land),
    5,
    'authenticated user reads all 5 countries (global read)'
);

------------------------------------------------------------
-- dim_land REVOKE writes (3 assertions)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_land (land_id, name) values ('IT', 'Italië') $$,
    '42501'
);

select throws_ok(
    $$ update public.dim_land set name = 'hacked' where land_id = 'BE' $$,
    '42501'
);

select throws_ok(
    $$ delete from public.dim_land where land_id = 'BE' $$,
    '42501'
);

------------------------------------------------------------
-- dim_land uppercase CHECK (1 assertion). Switch to service_role
-- to bypass REVOKE so the CHECK constraint fires.
------------------------------------------------------------

select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.dim_land (land_id, name) values ('be', 'lowercase') $$,
    '23514'
);

reset role;

------------------------------------------------------------
-- dim_legale_entiteit RLS insert: team A owner creates a legale entiteit
-- under Team A. (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select lives_ok(
    $$ insert into public.dim_legale_entiteit (basejump_account_id, werkgeverscategorie, naam, land_id, ondernemingsnr)
       values ('11111111-1111-1111-1111-111111111111', 1, 'Boekhouding BVBA', 'BE', '0403.019.261') $$,
    'team A owner can insert a legale entiteit under Team A'
);

------------------------------------------------------------
-- Cross-tenant filter: team B sees zero rows via RLS (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.dim_legale_entiteit),
    0,
    'Team B sees zero legale entiteiten (RLS filters Team A rows)'
);

------------------------------------------------------------
-- Cross-tenant INSERT block via WITH CHECK (1 assertion)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_legale_entiteit (basejump_account_id, werkgeverscategorie, naam, land_id)
       values ('11111111-1111-1111-1111-111111111111', 1, 'Team A hijack attempt', 'BE') $$,
    '42501'
);

------------------------------------------------------------
-- werkgeverscategorie CHECK: cat=4 invalid (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select throws_ok(
    $$ insert into public.dim_legale_entiteit (basejump_account_id, werkgeverscategorie, naam, land_id)
       values ('11111111-1111-1111-1111-111111111111', 4, 'invalid cat', 'BE') $$,
    '23514'
);

------------------------------------------------------------
-- Team-account trigger: personal-account FK raises (1 assertion).
-- team_a_owner's auto-created personal account (personal_account = true)
-- as the FK target.
------------------------------------------------------------

select throws_ok(
    format(
        $$ insert into public.dim_legale_entiteit (basejump_account_id, werkgeverscategorie, naam, land_id)
           values (%L, 1, 'personal attempt', 'BE') $$,
        (select id from basejump.accounts where personal_account = true and primary_owner_user_id = tests.get_supabase_uid('team_a_owner'))
    ),
    '23514'
);

------------------------------------------------------------
-- ON DELETE RESTRICT: cannot delete team A account while
-- legale_entiteit hangs on it (1 assertion). Runs as service_role
-- to bypass RLS/REVOKE so the FK RESTRICT genuinely fires.
------------------------------------------------------------

select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ delete from basejump.accounts where id = '11111111-1111-1111-1111-111111111111' $$,
    '23503'
);

select * from finish();
ROLLBACK;
