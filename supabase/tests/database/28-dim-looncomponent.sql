BEGIN;
create extension if not exists pgtap;

select plan(14);

select tests.create_supabase_user('test_reader');

------------------------------------------------------------
-- Schema shape (7 assertions)
------------------------------------------------------------

select has_table('public', 'dim_looncomponent', 'dim_looncomponent table exists');
select col_is_pk('public', 'dim_looncomponent', 'component_id', 'component_id is PK');
select col_is_fk('public', 'dim_looncomponent', 'sz_behandeling_id', 'sz_behandeling_id is FK to dim_sz_behandeling');

-- Gedragstags: verify type = boolean AND NOT NULL to prevent drift
select col_type_is('public', 'dim_looncomponent', 'rsz_plichtig', 'boolean', 'rsz_plichtig is boolean');
select col_type_is('public', 'dim_looncomponent', 'is_werkgeverskost', 'boolean', 'is_werkgeverskost is boolean');
select col_type_is('public', 'dim_looncomponent', 'telt_voor_vakantiegeld', 'boolean', 'telt_voor_vakantiegeld is boolean');
select col_type_is('public', 'dim_looncomponent', 'telt_voor_mu', 'boolean', 'telt_voor_mu is boolean');


------------------------------------------------------------
-- NOT NULL enforcement (4 assertions — one per boolean gedragstag)
------------------------------------------------------------

select col_not_null('public', 'dim_looncomponent', 'rsz_plichtig', 'rsz_plichtig NOT NULL');
select col_not_null('public', 'dim_looncomponent', 'is_werkgeverskost', 'is_werkgeverskost NOT NULL');
select col_not_null('public', 'dim_looncomponent', 'telt_voor_vakantiegeld', 'telt_voor_vakantiegeld NOT NULL');
select col_not_null('public', 'dim_looncomponent', 'telt_voor_mu', 'telt_voor_mu NOT NULL');


------------------------------------------------------------
-- Global read: authenticated user reads (empty table but query succeeds)
------------------------------------------------------------

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.dim_looncomponent),
    12,
    'T-012 seeded 12 canonieke looncomponenten (basisloon, bonus, wagen, etc)'
);


------------------------------------------------------------
-- REVOKE writes (1 assertion — sample)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_looncomponent (component_id, name, familie, rsz_plichtig, is_werkgeverskost, telt_voor_vakantiegeld, sz_behandeling_id, telt_voor_mu)
       values ('hack', 'Hack', 'x', true, true, true, 'normaal', true) $$,
    '42501'
);


------------------------------------------------------------
-- FK RESTRICT: cannot insert component with unknown sz_behandeling_id.
-- Switch to service_role to bypass REVOKE and reach FK constraint.
------------------------------------------------------------

select tests.clear_authentication();

select throws_ok(
    $$ insert into public.dim_looncomponent (component_id, name, familie, rsz_plichtig, is_werkgeverskost, telt_voor_vakantiegeld, sz_behandeling_id, telt_voor_mu)
       values ('test', 'Test', 'x', true, true, true, 'nonexistent_regime', true) $$,
    '23503'
);



select * from finish();
ROLLBACK;
