BEGIN;
-- ISS-085 refactor: setup als postgres met unique test-26 UUIDs,
-- RLS reads als authenticated.

create extension if not exists pgtap;

select plan(11);

select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values
    ('26260100-1111-1111-1111-111111111111', 'Team A', 'team-a-26', false, tests.get_supabase_uid('team_a_owner')),
    ('26260100-2222-2222-2222-222222222222', 'Team B', 'team-b-26', false, tests.get_supabase_uid('team_b_owner'));
insert into basejump.account_user (user_id, account_id, account_role) values
    (tests.get_supabase_uid('team_a_owner'), '26260100-1111-1111-1111-111111111111', 'owner'),
    (tests.get_supabase_uid('team_b_owner'), '26260100-2222-2222-2222-222222222222', 'owner');

insert into public.dim_org_unit (org_unit_id, owning_account_id, kind, name) values
    ('26260300-1111-1111-1111-111111111111', '26260100-1111-1111-1111-111111111111', 'business_unit', 'HR BU'),
    ('26260300-2222-1111-1111-111111111111', '26260100-1111-1111-1111-111111111111', 'departement', 'HR Departement');

-- Two flavor closures: 'statutair' self+parent, 'business' only self.
insert into public.bridge_hierarchie (hierarchie_id, ancestor_org_unit_id, descendant_org_unit_id, afstamming) values
    ('statutair', '26260300-1111-1111-1111-111111111111', '26260300-1111-1111-1111-111111111111', 0),
    ('statutair', '26260300-1111-1111-1111-111111111111', '26260300-2222-1111-1111-111111111111', 1),
    ('business', '26260300-1111-1111-1111-111111111111', '26260300-1111-1111-1111-111111111111', 0);


------------------------------------------------------------
-- Schema shape (4 asserts)
------------------------------------------------------------

select has_view('public', 'view_hierarchie_statutair', 'statutair view exists');
select has_view('public', 'view_hierarchie_business', 'business view exists');
select has_view('public', 'view_hierarchie_geografisch', 'geografisch view exists');
select has_view('public', 'view_hierarchie_kostenplaats', 'kostenplaats view exists');


------------------------------------------------------------
-- Flavor content: each view returns its own flavor's rows
------------------------------------------------------------

select tests.authenticate_as('team_a_owner');

select is(
    (select count(*)::int from public.view_hierarchie_statutair),
    2,
    'statutair view returns 2 rows (self + parent-child)'
);

select is(
    (select count(*)::int from public.view_hierarchie_business),
    1,
    'business view returns 1 row (self only)'
);


------------------------------------------------------------
-- Cross-flavor negatives: each view returns 0 rows van andere flavors
------------------------------------------------------------

select is(
    (select count(*)::int from public.view_hierarchie_geografisch),
    0,
    'geografisch view returns 0 rows (no closure for this flavor)'
);

select is(
    (select count(*)::int from public.view_hierarchie_kostenplaats),
    0,
    'kostenplaats view returns 0 rows (no closure for this flavor)'
);


------------------------------------------------------------
-- Join correctness: ancestor_name/descendant_name voor parent-child
-- statutair row matchen dim_org_unit values.
------------------------------------------------------------

select is(
    (select ancestor_name || ' → ' || descendant_name
       from public.view_hierarchie_statutair
       where afstamming = 1),
    'HR BU → HR Departement',
    'statutair view joins ancestor/descendant names correctly'
);


------------------------------------------------------------
-- Cross-tenant RLS erving: team B sees 0 rows via views
-- (base bridge_hierarchie RLS + dim_org_unit RLS fire via SECURITY INVOKER)
------------------------------------------------------------

select tests.authenticate_as('team_b_owner');

select is(
    (select count(*)::int from public.view_hierarchie_statutair),
    0,
    'Team B sees 0 statutair rows (RLS erving via SECURITY INVOKER)'
);

select is(
    (select count(*)::int from public.view_hierarchie_business),
    0,
    'Team B sees 0 business rows (RLS erving via SECURITY INVOKER)'
);


select * from finish();
ROLLBACK;
