BEGIN;
create extension if not exists pgtap;

select plan(15);

select tests.create_supabase_user('test_reader');

------------------------------------------------------------
-- Schema shape (2 assertions)
------------------------------------------------------------

select has_table('public', 'dim_sz_behandeling', 'dim_sz_behandeling table exists');
select col_is_pk('public', 'dim_sz_behandeling', 'sz_behandeling_id', 'sz_behandeling_id is PK');


------------------------------------------------------------
-- Seed (3 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_sz_behandeling),
    5,
    'seed created 5 SZ-regimes'
);

select is(
    (select regime_naam from public.dim_sz_behandeling where sz_behandeling_id = 'normaal'),
    'Normaal loon',
    'normaal regime naam correct'
);

select is(
    (select regime_naam from public.dim_sz_behandeling where sz_behandeling_id = 'vrijgesteld'),
    'Vrijgesteld van SZ',
    'vrijgesteld regime naam correct'
);


------------------------------------------------------------
-- Grondslag_type per regime (5 assertions — one per regime)
------------------------------------------------------------

select is(
    (select grondslag_type from public.dim_sz_behandeling where sz_behandeling_id = 'normaal'),
    'werkelijke_waarde',
    'normaal grondslag_type = werkelijke_waarde'
);

select is(
    (select grondslag_type from public.dim_sz_behandeling where sz_behandeling_id = 'vin_forfaitair'),
    'forfaitaire_waardering',
    'vin_forfaitair grondslag_type = forfaitaire_waardering'
);

select is(
    (select grondslag_type from public.dim_sz_behandeling where sz_behandeling_id = 'vin_bijzondere_formule'),
    'formule',
    'vin_bijzondere_formule grondslag_type = formule'
);

select is(
    (select grondslag_type from public.dim_sz_behandeling where sz_behandeling_id = 'vrijgesteld'),
    'nvt',
    'vrijgesteld grondslag_type = nvt'
);

select is(
    (select grondslag_type from public.dim_sz_behandeling where sz_behandeling_id = 'gunstregime_cap'),
    'gunstig_tot_plafond',
    'gunstregime_cap grondslag_type = gunstig_tot_plafond'
);


------------------------------------------------------------
-- Global read (1 assertion): authenticated user reads all 5 rows
------------------------------------------------------------

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.dim_sz_behandeling),
    5,
    'authenticated user reads all 5 SZ-regimes (global read)'
);


------------------------------------------------------------
-- REVOKE writes (3 assertions)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.dim_sz_behandeling (sz_behandeling_id, regime_naam, grondslag_type, bron_url) values ('hacked', 'Hack', 'nvt', 'x') $$,
    '42501'
);

select throws_ok(
    $$ update public.dim_sz_behandeling set regime_naam = 'hacked' where sz_behandeling_id = 'normaal' $$,
    '42501'
);

select throws_ok(
    $$ delete from public.dim_sz_behandeling where sz_behandeling_id = 'normaal' $$,
    '42501'
);


------------------------------------------------------------
-- grondslag_type CHECK constraint (1 assertion)
-- Switch to service_role to bypass REVOKE and reach CHECK.
------------------------------------------------------------

select tests.clear_authentication();

select throws_ok(
    $$ insert into public.dim_sz_behandeling (sz_behandeling_id, regime_naam, grondslag_type, bron_url) values ('invalid', 'Invalid', 'not_a_valid_type', 'x') $$,
    '23514'
);



select * from finish();
ROLLBACK;
