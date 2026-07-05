BEGIN;
-- ISS-085 refactor: alle inserts als postgres, RLS reads + WITH CHECK
-- als authenticated. dim_org_unit / map_entiteit_pc_competentie /
-- bridge_hierarchie hebben géén INSERT grant voor authenticated —
-- prod-pad = admin scripts / SECURITY DEFINER RPCs.

create extension if not exists pgtap;

select plan(21);

select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values
    ('25250100-1111-1111-1111-111111111111', 'Team A', 'team-a-25', false, tests.get_supabase_uid('team_a_owner')),
    ('25250100-2222-2222-2222-222222222222', 'Team B', 'team-b-25', false, tests.get_supabase_uid('team_b_owner'));
insert into basejump.account_user (user_id, account_id, account_role) values
    (tests.get_supabase_uid('team_a_owner'), '25250100-1111-1111-1111-111111111111', 'owner'),
    (tests.get_supabase_uid('team_b_owner'), '25250100-2222-2222-2222-222222222222', 'owner');

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('25250200-1111-1111-1111-111111111111', '25250100-1111-1111-1111-111111111111', 1, 'Team A BVBA', 'BE'),
    ('25250200-2222-2222-2222-222222222222', '25250100-2222-2222-2222-222222222222', 1, 'Team B BVBA', 'BE');


------------------------------------------------------------
-- Schema shape
------------------------------------------------------------

select has_table('public', 'dim_hierarchie', 'dim_hierarchie table exists');
select has_table('public', 'dim_org_unit', 'dim_org_unit table exists');
select has_table('public', 'bridge_hierarchie', 'bridge_hierarchie table exists');
select has_table('public', 'map_entiteit_pc_competentie', 'map_entiteit_pc_competentie table exists');


------------------------------------------------------------
-- dim_hierarchie seed
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
-- dim_hierarchie REVOKE writes
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select throws_ok(
    $$ insert into public.dim_hierarchie (hierarchie_id, name) values ('foo', 'Foo') $$,
    '42501'
);


------------------------------------------------------------
-- dim_org_unit inserts + kind-consistency CHECK als postgres
------------------------------------------------------------

select tests.clear_authentication();

select lives_ok(
    $$ insert into public.dim_org_unit (org_unit_id, owning_account_id, kind, name)
       values ('25250300-1111-1111-1111-111111111111', '25250100-1111-1111-1111-111111111111', 'team', 'Payroll Team') $$,
    'dim_org_unit insert (kind=team) succeeds (postgres role)'
);

select throws_ok(
    $$ insert into public.dim_org_unit (owning_account_id, kind, name)
       values ('25250100-1111-1111-1111-111111111111', 'legale_entiteit', 'Missing FK') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.dim_org_unit (owning_account_id, kind, name, legale_entiteit_id)
       values ('25250100-1111-1111-1111-111111111111', 'team', 'Wrong FK', '25250200-1111-1111-1111-111111111111') $$,
    '23514'
);


------------------------------------------------------------
-- bridge_hierarchie: closure insert (self + parent) als postgres
------------------------------------------------------------

insert into public.dim_org_unit (org_unit_id, owning_account_id, kind, name)
    values ('25250400-1111-1111-1111-111111111111', '25250100-1111-1111-1111-111111111111', 'departement', 'HR Departement');

select lives_ok(
    $$ insert into public.bridge_hierarchie (hierarchie_id, ancestor_org_unit_id, descendant_org_unit_id, afstamming)
       values ('statutair', '25250300-1111-1111-1111-111111111111', '25250300-1111-1111-1111-111111111111', 0),
              ('statutair', '25250300-1111-1111-1111-111111111111', '25250400-1111-1111-1111-111111111111', 1) $$,
    'closure table: self + parent-child rows insert'
);

select is(
    (select count(*)::int from public.bridge_hierarchie where hierarchie_id = 'statutair'),
    2,
    'bridge_hierarchie has 2 rows for statutair flavor'
);


------------------------------------------------------------
-- Cross-tenant RLS filter on dim_org_unit
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.dim_org_unit),
    0,
    'Team B sees 0 dim_org_unit rows (RLS filters Team A)'
);


------------------------------------------------------------
-- map_entiteit_pc_competentie insert + CHECK constraints als postgres
------------------------------------------------------------

select tests.clear_authentication();

select lives_ok(
    $$ insert into public.map_entiteit_pc_competentie (entiteit_id, activiteit, categorie, pc_id, geldig_van)
       values ('25250200-1111-1111-1111-111111111111', 'boekhouding', 1, '200', '2024-01-01') $$,
    'map row insert lukt (postgres role)'
);

select throws_ok(
    $$ insert into public.map_entiteit_pc_competentie (entiteit_id, activiteit, categorie, pc_id, geldig_van)
       values ('25250200-1111-1111-1111-111111111111', 'boekhouding', 4, '200', '2024-01-01') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.map_entiteit_pc_competentie (entiteit_id, activiteit, categorie, pc_id, geldig_van, geldig_tot)
       values ('25250200-1111-1111-1111-111111111111', 'boekhouding', 2, '200', '2024-06-01', '2024-01-01') $$,
    '23514'
);


------------------------------------------------------------
-- Cross-tenant RLS on map + bridge
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
-- Cross-tenant WITH CHECK block: team B als authenticated probeert
-- write op Team A refs. bridge_hierarchie en map_entiteit_pc_competentie
-- geven 42501 (INSERT grant ontbreekt sowieso, matcht productioneel).
------------------------------------------------------------

select throws_ok(
    $$ insert into public.bridge_hierarchie (hierarchie_id, ancestor_org_unit_id, descendant_org_unit_id, afstamming)
       values ('statutair', '25250300-1111-1111-1111-111111111111', '25250400-1111-1111-1111-111111111111', 1) $$,
    '42501'
);

select throws_ok(
    $$ insert into public.map_entiteit_pc_competentie (entiteit_id, activiteit, categorie, pc_id, geldig_van)
       values ('25250200-1111-1111-1111-111111111111', 'boekhouding', 1, '200', '2024-01-01') $$,
    '42501'
);


select * from finish();
ROLLBACK;
