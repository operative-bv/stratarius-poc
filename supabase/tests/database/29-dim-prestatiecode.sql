BEGIN;
create extension if not exists pgtap;

select plan(20);

select tests.create_supabase_user('test_reader');


------------------------------------------------------------
-- Schema shape (4 assertions)
------------------------------------------------------------

select has_table('public', 'dim_prestatiecode', 'dim_prestatiecode table exists');
select col_is_pk('public', 'dim_prestatiecode', 'prestatiecode', 'prestatiecode is PK');
select col_type_is('public', 'dim_prestatiecode', 'telt_voor_mu', 'boolean', 'telt_voor_mu is boolean');
select col_type_is('public', 'dim_prestatiecode', 'gelijkgesteld_rsz', 'boolean', 'gelijkgesteld_rsz is boolean');


------------------------------------------------------------
-- Boolean NOT NULL enforcement (3 assertions)
------------------------------------------------------------

select col_not_null('public', 'dim_prestatiecode', 'telt_voor_mu', 'telt_voor_mu NOT NULL');
select col_not_null('public', 'dim_prestatiecode', 'gelijkgesteld_rsz', 'gelijkgesteld_rsz NOT NULL');
select col_not_null('public', 'dim_prestatiecode', 'gelijkgesteld_vakantiegeld', 'gelijkgesteld_vakantiegeld NOT NULL');


------------------------------------------------------------
-- Seed count (1 assertion)
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_prestatiecode),
    12,
    'seed created 12 canonical prestatiecodes'
);


------------------------------------------------------------
-- Kritische invarianten uit PDF Laag 2 (8 assertions)
------------------------------------------------------------

-- Arbeidsongeschikt 2 fasen: gewaarborgd = werkgever, mutualiteit = mutualiteit
select is(
    (select betaalbron from public.dim_prestatiecode where prestatiecode = 'arbeidsongeschikt_gewaarborgd'),
    'werkgever',
    'arbeidsongeschikt fase 1 (gewaarborgd loon) betaalbron = werkgever'
);
select is(
    (select betaalbron from public.dim_prestatiecode where prestatiecode = 'arbeidsongeschikt_mutualiteit'),
    'mutualiteit',
    'arbeidsongeschikt fase 2 (mutualiteit/RIZIV) betaalbron = mutualiteit'
);

-- Vakantie arbeider/bediende splitsing
select is(
    (select betaalbron from public.dim_prestatiecode where prestatiecode = 'vakantie_wettelijk_arb'),
    'vakantiekas',
    'vakantie arbeider betaalbron = vakantiekas'
);
select is(
    (select gelijkgesteld_vakantiegeld from public.dim_prestatiecode where prestatiecode = 'vakantie_wettelijk_arb'),
    false,
    'vakantie arbeider gelijkgesteld_vakantiegeld = false (opbouw zit al in kas)'
);
select is(
    (select gelijkgesteld_vakantiegeld from public.dim_prestatiecode where prestatiecode = 'vakantie_wettelijk_bed'),
    true,
    'vakantie bediende gelijkgesteld_vakantiegeld = true (opbouw volgende jaar)'
);

-- Tijdelijke urenvermindering: Principe IV μ-invariant + betaalbron
select is(
    (select telt_voor_mu from public.dim_prestatiecode where prestatiecode = 'tijdelijke_urenvermindering'),
    false,
    'tijdelijke_urenvermindering telt_voor_mu = false (Principe IV: fte_breuk blijft 1, mu zakt)'
);
select is(
    (select betaalbron from public.dim_prestatiecode where prestatiecode = 'tijdelijke_urenvermindering'),
    'rva',
    'tijdelijke_urenvermindering betaalbron = rva'
);

-- Moederschapsrust: RIZIV zonder gewaarborgd loon fase
select is(
    (select betaalbron from public.dim_prestatiecode where prestatiecode = 'moederschapsrust'),
    'riziv',
    'moederschapsrust betaalbron = riziv (geen gewaarborgd loon fase)'
);


------------------------------------------------------------
-- Overuren toeslag_pct (Principe II behavioral tag, 2 assertions)
------------------------------------------------------------

select is(
    (select toeslag_pct from public.dim_prestatiecode where prestatiecode = 'overuren_50'),
    0.50::numeric,
    'overuren_50 toeslag_pct = 0.50'
);
select is(
    (select toeslag_pct from public.dim_prestatiecode where prestatiecode = 'overuren_100'),
    1.00::numeric,
    'overuren_100 toeslag_pct = 1.00'
);


------------------------------------------------------------
-- REVOKE writes (1 assertion — sample)
------------------------------------------------------------

select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.dim_prestatiecode (prestatiecode, naam, familie, telt_voor_mu, gelijkgesteld_rsz, gelijkgesteld_vakantiegeld, betaalbron)
       values ('hack', 'Hack', 'x', true, true, true, 'werkgever') $$,
    '42501'
);


------------------------------------------------------------
-- betaalbron CHECK enforcement (1 assertion). service_role bypasses REVOKE.
------------------------------------------------------------

select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.dim_prestatiecode (prestatiecode, naam, familie, telt_voor_mu, gelijkgesteld_rsz, gelijkgesteld_vakantiegeld, betaalbron)
       values ('bad', 'Bad', 'x', true, true, true, 'invalid_source') $$,
    '23514'
);

reset role;


select * from finish();
ROLLBACK;
