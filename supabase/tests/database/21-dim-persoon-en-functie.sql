BEGIN;
create extension if not exists pgtap;

select plan(15);

-- Setup: two team accounts, one owner each. Personal accounts auto-created too.
select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

-- Team A: owner creates a team account
select tests.authenticate_as('team_a_owner');
insert into basejump.accounts (id, name, slug, personal_account)
values ('11111111-1111-1111-1111-111111111111', 'Team A', 'team-a', false);

-- Team B: owner creates a team account
select tests.authenticate_as('team_b_owner');
insert into basejump.accounts (id, name, slug, personal_account)
values ('22222222-2222-2222-2222-222222222222', 'Team B', 'team-b', false);

------------------------------------------------------------
-- Schema shape
------------------------------------------------------------

select has_table('public', 'dim_persoon', 'dim_persoon table exists');
select has_table('public', 'dim_functie', 'dim_functie table exists');
select col_is_pk('public', 'dim_persoon', 'persoon_id', 'dim_persoon.persoon_id is PK');
select col_is_pk('public', 'dim_functie', 'functie_id', 'dim_functie.functie_id is PK');
select col_is_fk('public', 'dim_persoon', 'owning_account_id', 'dim_persoon.owning_account_id is FK');
select col_is_fk('public', 'dim_functie', 'owning_account_id', 'dim_functie.owning_account_id is FK');

------------------------------------------------------------
-- RLS insert: team A owner can insert a persoon under Team A
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select lives_ok(
    $$ insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum, opleidingsniveau)
       values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'v', '1985-05-15', 'bachelor') $$,
    'Team A owner can insert a persoon under Team A'
);

select lives_ok(
    $$ insert into public.dim_functie (functie_id, owning_account_id, functienaam, functieniveau, genderneutrale_weging)
       values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'HR Adviseur', 12, 0.98500000) $$,
    'Team A owner can insert a functie under Team A'
);

------------------------------------------------------------
-- Cross-tenant RLS: Team B owner cannot see Team A rows
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

-- With column-level REVOKE on geslacht/opleidingsniveau, SELECT explicit columns
-- that are still readable (persoon_id, owning_account_id) shows 0 rows via RLS.
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
-- Trigger: cmp_ok(updated_at > created_at) omitted per ISS-012.
-- basejump.trigger_set_timestamps() uses now(), which returns
-- transaction-start time. Inside a single BEGIN/ROLLBACK test, INSERT
-- and UPDATE both stamp identical timestamps → cmp_ok(>) would fail.
-- Correctness of the trigger is verified by inspection of Basejump's
-- reused trigger function; behaviour under multi-statement production
-- traffic is covered by manual QA once Supabase is running.
------------------------------------------------------------


------------------------------------------------------------
-- GDPR column-level REVOKE: authenticated cannot SELECT geslacht.
-- Use SQLSTATE-only match (42501 = insufficient_privilege) — exact error text
-- differs between Postgres versions (table-level vs column-level phrasing).
------------------------------------------------------------

select throws_ok(
    $$ select geslacht from public.dim_persoon $$,
    '42501'
);

select throws_ok(
    $$ select opleidingsniveau from public.dim_persoon $$,
    '42501'
);

------------------------------------------------------------
-- Cross-tenant INSERT: team A owner cannot insert a row that says
-- owning_account_id = Team B. WITH CHECK enforces the new row's tenant.
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select throws_ok(
    $$ insert into public.dim_persoon (owning_account_id, geboortedatum)
       values ('22222222-2222-2222-2222-222222222222', '1990-01-01') $$,
    '42501'
);

------------------------------------------------------------
-- Sanity CHECK on geboortedatum (SQLSTATE 23514 = check_violation)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_persoon (owning_account_id, geboortedatum)
       values ('11111111-1111-1111-1111-111111111111', date '1850-01-01') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.dim_persoon (owning_account_id, geboortedatum)
       values ('11111111-1111-1111-1111-111111111111', current_date + interval '1 day') $$,
    '23514'
);

select * from finish();
ROLLBACK;
