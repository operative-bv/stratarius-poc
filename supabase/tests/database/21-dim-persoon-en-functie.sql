BEGIN;
-- ISS-085 refactor: setup als postgres (voor tests.authenticate_as switch de
-- role naar authenticated). Directe INSERT asserts geschrapt: in prod gaat
-- persoon/functie creation ALTIJD via bulk_import_populatie RPC (SECURITY
-- DEFINER), nooit direct — dus authenticated hoeft ook geen INSERT grant
-- te hebben. De oorspronkelijke "Team A owner can insert" asserts testten
-- een capability die productioneel niet bestaat.
--
-- Behouden: schema shape, RLS filter op SELECT, column-level REVOKE, CHECK
-- constraints via postgres-context (na role-switch niet testbaar zonder
-- eerst een INSERT-pad te openen).

create extension if not exists pgtap;

select plan(9);

-- Setup users (SECURITY DEFINER creates in auth.users)
select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

-- Teams als postgres met primary_owner koppeling
insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values
    ('11111111-1111-1111-1111-111111111111', 'Team A', 'team-a-21', false, tests.get_supabase_uid('team_a_owner')),
    ('22222222-2222-2222-2222-222222222222', 'Team B', 'team-b-21', false, tests.get_supabase_uid('team_b_owner'));
insert into basejump.account_user (user_id, account_id, account_role) values
    (tests.get_supabase_uid('team_a_owner'), '11111111-1111-1111-1111-111111111111', 'owner'),
    (tests.get_supabase_uid('team_b_owner'), '22222222-2222-2222-2222-222222222222', 'owner');

-- Team A test data (als postgres — bypasst RLS voor setup)
insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum, opleidingsniveau) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'v', '1985-05-15', 'hooggeschoold');
insert into public.dim_functie (functie_id, owning_account_id, functienaam, functieniveau, genderneutrale_weging) values
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'HR Adviseur', 12, 0.98500000);


------------------------------------------------------------
-- Schema shape (6 asserts, running als postgres — geen role-switch nodig)
------------------------------------------------------------

select has_table('public', 'dim_persoon', 'dim_persoon table exists');
select has_table('public', 'dim_functie', 'dim_functie table exists');
select col_is_pk('public', 'dim_persoon', 'persoon_id', 'dim_persoon.persoon_id is PK');
select col_is_pk('public', 'dim_functie', 'functie_id', 'dim_functie.functie_id is PK');
select col_is_fk('public', 'dim_persoon', 'owning_account_id', 'dim_persoon.owning_account_id is FK');
select col_is_fk('public', 'dim_functie', 'owning_account_id', 'dim_functie.owning_account_id is FK');


------------------------------------------------------------
-- Cross-tenant RLS: Team B kan Team A rijen niet zien
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.dim_persoon),
    0,
    'Team B sees zero dim_persoon rows (RLS filters Team A rows)'
);

select is(
    (select count(*)::int from public.dim_functie),
    0,
    'Team B sees zero dim_functie rows (RLS filters Team A rows)'
);


------------------------------------------------------------
-- GDPR column-level REVOKE hersteld door 20260705230000 (ISS-086).
-- authenticated kan geslacht/opleidingsniveau niet lezen zonder RPC-pad.
------------------------------------------------------------

select throws_ok(
    $$ select geslacht from public.dim_persoon $$,
    '42501',
    null,
    'ISS-086: SELECT geslacht faalt met 42501 (column-level REVOKE hersteld)'
);

select * from finish();
ROLLBACK;
