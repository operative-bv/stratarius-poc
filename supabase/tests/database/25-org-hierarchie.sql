BEGIN;
create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(21);

-- Setup: two team accounts with a legale entiteit each.
select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

select tests.authenticate_as('team_a_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('11111111-1111-1111-1111-111111111111', 'Team A', 'team-a', false);

insert into public.dim_legale_entiteit (legale_entiteit_id, basejump_account_id, werkgeverscategorie, naam, land_id) values
    ('aaaaaaaa-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 1, 'Team A BVBA', 'BE');

select tests.authenticate_as('team_b_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('22222222-2222-2222-2222-222222222222', 'Team B', 'team-b', false);

insert into public.dim_legale_entiteit (legale_entiteit_id, basejump_account_id, werkgeverscategorie, naam, land_id) values
    ('aaaaaaaa-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 1, 'Team B BVBA', 'BE');


------------------------------------------------------------
-- Schema shape (4 assertions)
------------------------------------------------------------

select has_table('public', 'dim_hierarchie', 'dim_hierarchie table exists');
select has_table('public', 'dim_org_unit', 'dim_org_unit table exists');
select has_table('public', 'bridge_hierarchie', 'bridge_hierarchie table exists');
select has_table('public', 'map_entiteit_pc_competentie', 'map_entiteit_pc_competentie table exists');


------------------------------------------------------------
-- dim_hierarchie seed (3 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_hierarchie),
    4,
    'seed created 4 hierarchie flavors'
);

select is(
    (select name from public.dim_hierarchie where hierarchie_id = 'statutair'),
    'Statutaire hiërarchie',
    'statutair flavor name correct'
);

select is(
    (select name from public.dim_hierarchie where hierarchie_id = 'kostenplaats'),
    'Kostenplaats hiërarchie',
    'kostenplaats flavor name correct (distinct van dim_org_unit.kind=kostenplaats)'
);


------------------------------------------------------------
-- dim_hierarchie REVOKE writes (1 assertion — sample)
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select throws_ok(
    $$ insert into public.dim_hierarchie (hierarchie_id, name) values ('foo', 'Foo') $$,
    '42501'
);


------------------------------------------------------------
-- dim_org_unit RLS insert + kind-consistency CHECK (3 assertions)
------------------------------------------------------------

-- Valid: kind='team' with no legale_entiteit_id
select lives_ok(
    $$ insert into public.dim_org_unit (org_unit_id, owning_account_id, kind, name)
       values ('bbbbbbbb-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'team', 'Payroll Team') $$,
    'team A owner inserts dim_org_unit (kind=team) successfully'
);

-- Invalid: kind='legale_entiteit' zonder legale_entiteit_id (biconditional CHECK)
select throws_ok(
    $$ insert into public.dim_org_unit (owning_account_id, kind, name)
       values ('11111111-1111-1111-1111-111111111111', 'legale_entiteit', 'Missing FK') $$,
    '23514'
);

-- Invalid: kind='team' MET legale_entiteit_id (biconditional CHECK)
select throws_ok(
    $$ insert into public.dim_org_unit (owning_account_id, kind, name, legale_entiteit_id)
       values ('11111111-1111-1111-1111-111111111111', 'team', 'Wrong FK', 'aaaaaaaa-1111-1111-1111-111111111111') $$,
    '23514'
);


------------------------------------------------------------
-- bridge_hierarchie: closure insert (self + parent) (2 assertions)
------------------------------------------------------------

-- Create a second org_unit as descendant.
insert into public.dim_org_unit (org_unit_id, owning_account_id, kind, name)
    values ('bbbbbbbb-2222-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'departement', 'HR Departement');

select lives_ok(
    $$ insert into public.bridge_hierarchie (hierarchie_id, ancestor_org_unit_id, descendant_org_unit_id, afstamming)
       values ('statutair', 'bbbbbbbb-1111-1111-1111-111111111111', 'bbbbbbbb-1111-1111-1111-111111111111', 0),
              ('statutair', 'bbbbbbbb-1111-1111-1111-111111111111', 'bbbbbbbb-2222-1111-1111-111111111111', 1) $$,
    'closure table: self + parent-child rows insert'
);

select is(
    (select count(*)::int from public.bridge_hierarchie where hierarchie_id = 'statutair'),
    2,
    'bridge_hierarchie has 2 rows for statutair flavor'
);


------------------------------------------------------------
-- Cross-tenant RLS filter on dim_org_unit (1 assertion)
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.dim_org_unit),
    0,
    'Team B sees 0 dim_org_unit rows (RLS filters Team A)'
);


------------------------------------------------------------
-- map_entiteit_pc_competentie: insert + categorie CHECK + effective-dating CHECK (3 assertions)
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select lives_ok(
    $$ insert into public.map_entiteit_pc_competentie (entiteit_id, activiteit, categorie, pc_id, geldig_van)
       values ('aaaaaaaa-1111-1111-1111-111111111111', 'boekhouding', 1, '200', '2024-01-01') $$,
    'team A owner inserts map row'
);

select throws_ok(
    $$ insert into public.map_entiteit_pc_competentie (entiteit_id, activiteit, categorie, pc_id, geldig_van)
       values ('aaaaaaaa-1111-1111-1111-111111111111', 'boekhouding', 4, '200', '2024-01-01') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.map_entiteit_pc_competentie (entiteit_id, activiteit, categorie, pc_id, geldig_van, geldig_tot)
       values ('aaaaaaaa-1111-1111-1111-111111111111', 'boekhouding', 2, '200', '2024-06-01', '2024-01-01') $$,
    '23514'
);


------------------------------------------------------------
-- Cross-tenant RLS on map + bridge (1 assertion each = 2 assertions)
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.map_entiteit_pc_competentie),
    0,
    'Team B sees 0 map rows (RLS filters via transitive tenant)'
);

select is(
    (select count(*)::int from public.bridge_hierarchie),
    0,
    'Team B sees 0 bridge_hierarchie rows (RLS filters via ancestor+descendant)'
);


------------------------------------------------------------
-- Cross-tenant WITH CHECK block: team B attempts write against Team A refs
-- (F2 + F5). Both should raise 42501 via WITH CHECK.
------------------------------------------------------------

-- bridge: team B tries to insert bridge row for Team A's org_unit chain
select throws_ok(
    $$ insert into public.bridge_hierarchie (hierarchie_id, ancestor_org_unit_id, descendant_org_unit_id, afstamming)
       values ('statutair', 'bbbbbbbb-1111-1111-1111-111111111111', 'bbbbbbbb-2222-1111-1111-111111111111', 1) $$,
    '42501'
);

-- map: team B tries to insert map row referencing Team A's entiteit
select throws_ok(
    $$ insert into public.map_entiteit_pc_competentie (entiteit_id, activiteit, categorie, pc_id, geldig_van)
       values ('aaaaaaaa-1111-1111-1111-111111111111', 'boekhouding', 1, '200', '2024-01-01') $$,
    '42501'
);


select * from finish();
ROLLBACK;
