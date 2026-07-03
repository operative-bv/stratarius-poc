BEGIN;
create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(12);

-- Setup: authenticated user to prove global read.
select tests.create_supabase_user('test_reader');

------------------------------------------------------------
-- Schema shape
------------------------------------------------------------

select has_table('public', 'dim_pc', 'dim_pc table exists');
select col_is_pk('public', 'dim_pc', 'pc_id', 'dim_pc.pc_id is PK');
select col_is_fk('public', 'dim_pc', 'parent_pc_id', 'dim_pc.parent_pc_id is FK');

------------------------------------------------------------
-- Seed count: 11 PCs from migration
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_pc),
    11,
    'seed created 11 PCs'
);

select is(
    (select name from public.dim_pc where pc_id = '200'),
    'Aanvullend paritair comité voor bedienden',
    'PC 200 seed name correct'
);

select is(
    (select name from public.dim_pc where pc_id = '302'),
    'Hotelbedrijf',
    'PC 302 seed name correct'
);

------------------------------------------------------------
-- Global read: authenticated user reads all seed rows
------------------------------------------------------------

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.dim_pc),
    11,
    'authenticated user reads all 11 PCs (global read)'
);

------------------------------------------------------------
-- REVOKE writes: authenticated cannot INSERT / UPDATE / DELETE
-- SQLSTATE 42501 = insufficient_privilege
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_pc (pc_id, name) values ('999', 'not allowed') $$,
    '42501'
);

select throws_ok(
    $$ update public.dim_pc set name = 'hacked' where pc_id = '200' $$,
    '42501'
);

select throws_ok(
    $$ delete from public.dim_pc where pc_id = '200' $$,
    '42501'
);

------------------------------------------------------------
-- CHECK constraint on status. Set local role service_role to bypass
-- REVOKE and reach the CHECK layer. Basejump test helpers don't ship
-- authenticate_as_service_role() so use raw role switch.
------------------------------------------------------------

select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.dim_pc (pc_id, name, status) values ('998', 'bad status', 'invalid') $$,
    '23514'
);

------------------------------------------------------------
-- Parent FK: ON DELETE RESTRICT blocks parent delete when child exists.
-- Runs as service_role: RLS bypassed, REVOKE bypassed, only FK constraint
-- fires. SQLSTATE 23503 = foreign_key_violation.
------------------------------------------------------------

insert into public.dim_pc (pc_id, name, parent_pc_id) values ('200.99', 'Test Sub-PC', '200');

select throws_ok(
    $$ delete from public.dim_pc where pc_id = '200' $$,
    '23503'
);

-- Note: cmp_ok(updated_at > created_at) trigger test omitted —
-- basejump.trigger_set_timestamps uses now() which returns
-- transaction-start time, so INSERT+UPDATE in the same tx yield
-- identical timestamps. Documented as ISS-011. Trigger correctness
-- verified by inspection of migration + Basejump reuse.

select * from finish();
ROLLBACK;
