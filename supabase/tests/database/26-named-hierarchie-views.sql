BEGIN;
create extension if not exists pgtap;

select plan(11);

-- Setup: two team accounts, org_units in team A, closure rows for 2 flavors.
select tests.create_supabase_user('team_a_owner');
select tests.create_supabase_user('team_b_owner');

select tests.authenticate_as('team_a_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('11111111-1111-1111-1111-111111111111', 'Team A', 'team-a', false);

insert into public.dim_org_unit (org_unit_id, owning_account_id, kind, name) values
    ('bbbbbbbb-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'business_unit', 'HR BU'),
    ('bbbbbbbb-2222-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'departement', 'HR Departement');

-- Two flavor closures: 'statutair' has self+parent rows, 'business' has only self rows.
insert into public.bridge_hierarchie (hierarchie_id, ancestor_org_unit_id, descendant_org_unit_id, afstamming) values
    ('statutair', 'bbbbbbbb-1111-1111-1111-111111111111', 'bbbbbbbb-1111-1111-1111-111111111111', 0),
    ('statutair', 'bbbbbbbb-1111-1111-1111-111111111111', 'bbbbbbbb-2222-1111-1111-111111111111', 1),
    ('business', 'bbbbbbbb-1111-1111-1111-111111111111', 'bbbbbbbb-1111-1111-1111-111111111111', 0);

select tests.authenticate_as('team_b_owner');
insert into basejump.accounts (id, name, slug, personal_account) values
    ('22222222-2222-2222-2222-222222222222', 'Team B', 'team-b', false);


------------------------------------------------------------
-- Schema shape (4 assertions)
------------------------------------------------------------

select has_view('public', 'view_hierarchie_statutair', 'statutair view exists');
select has_view('public', 'view_hierarchie_business', 'business view exists');
select has_view('public', 'view_hierarchie_geografisch', 'geografisch view exists');
select has_view('public', 'view_hierarchie_kostenplaats', 'kostenplaats view exists');


------------------------------------------------------------
-- Flavor content: each view returns its own flavor's rows (2 assertions)
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
-- Cross-flavor negatives (F1): each view returns 0 rows from other flavors
-- (2 assertions)
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
-- Join correctness (F3): ancestor_name/descendant_name for the parent-child
-- statutair row match dim_org_unit values (1 assertion)
------------------------------------------------------------

select is(
    (select ancestor_name || ' → ' || descendant_name
       from public.view_hierarchie_statutair
       where afstamming = 1),
    'HR BU → HR Departement',
    'statutair view joins ancestor/descendant names correctly'
);


------------------------------------------------------------
-- Cross-tenant RLS erving (2 assertions): team B sees 0 rows via views
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
