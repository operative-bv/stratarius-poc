BEGIN;
create extension if not exists pgtap;

select plan(19);

-- Setup: two team accounts, each with a legale entiteit, persoon and functie.
select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

-- Team A
select tests.authenticate_as('team_a_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('11111111-1111-1111-1111-111111111111', 'Team A', 'team-a', false);

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('aaaaaaaa-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 1, 'Team A BVBA', 'BE');

insert into public.dim_persoon (persoon_id, owning_account_id, geboortedatum) values
    ('cccccccc-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', '1985-05-15');

insert into public.dim_functie (functie_id, owning_account_id, functienaam) values
    ('dddddddd-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'HR Adviseur');

-- Team B
select tests.authenticate_as('team_b_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('22222222-2222-2222-2222-222222222222', 'Team B', 'team-b', false);

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('aaaaaaaa-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 1, 'Team B BVBA', 'BE');


------------------------------------------------------------
-- Schema shape (7 assertions)
------------------------------------------------------------

select has_table('public', 'dim_contract', 'dim_contract table exists');
select col_is_pk('public', 'dim_contract', 'contract_id', 'contract_id is PK');
select col_is_fk('public', 'dim_contract', 'persoon_id', 'persoon_id is FK');
select col_is_fk('public', 'dim_contract', 'functie_id', 'functie_id is FK');
select col_is_fk('public', 'dim_contract', 'legale_entiteit_id', 'legale_entiteit_id is FK');
select col_is_fk('public', 'dim_contract', 'pc_id', 'pc_id is FK');
select col_is_fk('public', 'dim_contract', 'vorige_contract_id', 'vorige_contract_id is self-FK');


------------------------------------------------------------
-- Insert first contract under Team A (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select lives_ok(
    $$ insert into public.dim_contract (contract_id, persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('11111111-cccc-1111-1111-111111111111',
               'cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'bediende', 1.0000, '2024-01-01') $$,
    'team A owner can insert first contract'
);


------------------------------------------------------------
-- Effective-dating CHECK: geldig_van < geldig_tot (1 assertion)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van, geldig_tot)
       values ('cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'bediende', 0.5000, '2024-02-01', '2024-01-01') $$,
    '23514'
);


------------------------------------------------------------
-- Uitgestelde wetgeving: future geldig_van accepted (1 assertion)
------------------------------------------------------------

select lives_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'bediende', 0.8000, (current_date + interval '90 days')::date) $$,
    'future geldig_van accepted (uitgestelde wetgeving)'
);


------------------------------------------------------------
-- fte_breuk boundary CHECKs (4 assertions)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'bediende', 0, '2024-03-01') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'bediende', 1.0001, '2024-04-01') $$,
    '23514'
);

select lives_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'bediende', 0.0001, '2024-05-01') $$,
    'fte_breuk = 0.0001 accepted (smallest legal deeltijds)'
);

select lives_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'bediende', 1.0000, '2024-06-01') $$,
    'fte_breuk = 1.0000 accepted (voltijds boundary)'
);


------------------------------------------------------------
-- status CHECK: 'kader' rejected (1 assertion)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'kader', 1.0000, '2024-07-01') $$,
    '23514'
);


------------------------------------------------------------
-- Versioning-keten: v2 met vorige_contract_id → v1 (1 assertion)
------------------------------------------------------------

select lives_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van, vorige_contract_id, reden)
       values ('cccccccc-1111-1111-1111-111111111111',
               'dddddddd-1111-1111-1111-111111111111',
               'aaaaaaaa-1111-1111-1111-111111111111',
               '200', 'bediende', 0.8000, '2025-01-01',
               '11111111-cccc-1111-1111-111111111111', 'indexering + urenwijziging') $$,
    'versioning keten: v2 with vorige_contract_id link accepted'
);


------------------------------------------------------------
-- Cross-tenant filter: Team B sees zero contracts (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.dim_contract),
    0,
    'Team B sees zero contracts (RLS filters Team A rows via transitive tenant)'
);


------------------------------------------------------------
-- Cross-tenant INSERT block via WITH CHECK (1 assertion).
-- Team B attempts to write a contract targeting Team A's legale_entiteit.
------------------------------------------------------------

select throws_ok(
    format(
        $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
           values (%L, %L, %L, '200', 'bediende', 1.0000, '2024-01-01') $$,
        'cccccccc-1111-1111-1111-111111111111',
        'dddddddd-1111-1111-1111-111111111111',
        'aaaaaaaa-1111-1111-1111-111111111111'
    ),
    '42501'
);


------------------------------------------------------------
-- FK ON DELETE RESTRICT: cannot delete persoon while contract hangs on it.
-- Runs as service_role to bypass RLS/REVOKE so the FK RESTRICT genuinely
-- fires (23503) instead of a permission error (42501). (1 assertion)
------------------------------------------------------------

select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ delete from public.dim_persoon where persoon_id = 'cccccccc-1111-1111-1111-111111111111' $$,
    '23503'
);

reset role;

select * from finish();
ROLLBACK;
