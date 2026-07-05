BEGIN;
-- ISS-085 refactor: setup + CHECK constraints als postgres
-- (dim_contract heeft geen INSERT grant voor authenticated — prod
-- gebruikt bulk_import RPC). RLS reads + cross-tenant WITH CHECK als
-- authenticated.

create extension if not exists pgtap;

select plan(19);

select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values
    ('24240100-1111-1111-1111-111111111111', 'Team A', 'team-a-24t', false, tests.get_supabase_uid('team_a_owner')),
    ('24240100-2222-2222-2222-222222222222', 'Team B', 'team-b-24t', false, tests.get_supabase_uid('team_b_owner'));
insert into basejump.account_user (user_id, account_id, account_role) values
    (tests.get_supabase_uid('team_a_owner'), '24240100-1111-1111-1111-111111111111', 'owner'),
    (tests.get_supabase_uid('team_b_owner'), '24240100-2222-2222-2222-222222222222', 'owner');

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('aa002400-1111-1111-1111-111111111111', '24240100-1111-1111-1111-111111111111', 1, 'Team A BVBA', 'BE'),
    ('aa002400-2222-2222-2222-222222222222', '24240100-2222-2222-2222-222222222222', 1, 'Team B BVBA', 'BE');

insert into public.dim_persoon (persoon_id, owning_account_id, geboortedatum) values
    ('24240300-1111-1111-1111-111111111111', '24240100-1111-1111-1111-111111111111', '1985-05-15');

insert into public.dim_functie (functie_id, owning_account_id, functienaam) values
    ('24240400-1111-1111-1111-111111111111', '24240100-1111-1111-1111-111111111111', 'HR Adviseur');


------------------------------------------------------------
-- Schema shape (7 asserts)
------------------------------------------------------------

select has_table('public', 'dim_contract', 'dim_contract table exists');
select col_is_pk('public', 'dim_contract', 'contract_id', 'contract_id is PK');
select col_is_fk('public', 'dim_contract', 'persoon_id', 'persoon_id is FK');
select col_is_fk('public', 'dim_contract', 'functie_id', 'functie_id is FK');
select col_is_fk('public', 'dim_contract', 'legale_entiteit_id', 'legale_entiteit_id is FK');
select col_is_fk('public', 'dim_contract', 'pc_id', 'pc_id is FK');
select col_is_fk('public', 'dim_contract', 'vorige_contract_id', 'vorige_contract_id is self-FK');


------------------------------------------------------------
-- Initial contract insert als postgres (dim_contract heeft geen INSERT
-- grant voor authenticated; prod-pad = bulk_import_populatie RPC).
------------------------------------------------------------

select lives_ok(
    $$ insert into public.dim_contract (contract_id, persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('24240500-1111-1111-1111-111111111111',
               '24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'bediende', 1.0000, '2024-01-01') $$,
    'contract insert lukt (postgres role, RLS bypassed voor setup)'
);


------------------------------------------------------------
-- Effective-dating CHECK: geldig_van < geldig_tot
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van, geldig_tot)
       values ('24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'bediende', 0.5000, '2024-02-01', '2024-01-01') $$,
    '23514'
);


------------------------------------------------------------
-- Uitgestelde wetgeving: future geldig_van accepted
------------------------------------------------------------

select lives_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'bediende', 0.8000, (current_date + interval '90 days')::date) $$,
    'future geldig_van accepted (uitgestelde wetgeving)'
);


------------------------------------------------------------
-- fte_breuk boundary CHECKs (4 asserts)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'bediende', 0, '2024-03-01') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'bediende', 1.0001, '2024-04-01') $$,
    '23514'
);

select lives_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'bediende', 0.0001, '2024-05-01') $$,
    'fte_breuk = 0.0001 accepted (smallest legal deeltijds)'
);

select lives_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'bediende', 1.0000, '2024-06-01') $$,
    'fte_breuk = 1.0000 accepted (voltijds boundary)'
);


------------------------------------------------------------
-- status CHECK: 'kader' rejected
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
       values ('24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'kader', 1.0000, '2024-07-01') $$,
    '23514'
);


------------------------------------------------------------
-- Versioning-keten: v2 met vorige_contract_id → v1
------------------------------------------------------------

select lives_ok(
    $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van, vorige_contract_id, reden)
       values ('24240300-1111-1111-1111-111111111111',
               '24240400-1111-1111-1111-111111111111',
               'aa002400-1111-1111-1111-111111111111',
               '200', 'bediende', 0.8000, '2025-01-01',
               '24240500-1111-1111-1111-111111111111', 'indexering + urenwijziging') $$,
    'versioning keten: v2 with vorige_contract_id link accepted'
);


------------------------------------------------------------
-- Cross-tenant filter: Team B ziet zero contracts
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.dim_contract),
    0,
    'Team B sees zero contracts (RLS filters Team A rows via transitive tenant)'
);


------------------------------------------------------------
-- Cross-tenant INSERT block via WITH CHECK. Team B als authenticated
-- probeert dim_contract insert op Team A's legale_entiteit → 42501
-- (INSERT grant ontbreekt sowieso — matcht productioneel gedrag).
------------------------------------------------------------

select throws_ok(
    format(
        $$ insert into public.dim_contract (persoon_id, functie_id, legale_entiteit_id, pc_id, status, fte_breuk, geldig_van)
           values (%L, %L, %L, '200', 'bediende', 1.0000, '2024-01-01') $$,
        '24240300-1111-1111-1111-111111111111',
        '24240400-1111-1111-1111-111111111111',
        'aa002400-1111-1111-1111-111111111111'
    ),
    '42501'
);


------------------------------------------------------------
-- FK ON DELETE RESTRICT: dim_persoon delete geblokkeerd door
-- contract-FK. Reset naar postgres om REVOKE/RLS te bypassen.
------------------------------------------------------------

select tests.clear_authentication();

select throws_ok(
    $$ delete from public.dim_persoon where persoon_id = '24240300-1111-1111-1111-111111111111' $$,
    '23503'
);

select * from finish();
ROLLBACK;
