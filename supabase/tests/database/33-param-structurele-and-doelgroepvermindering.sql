BEGIN;
create extension if not exists pgtap;

select plan(41);

select tests.create_supabase_user('test_reader');


------------------------------------------------------------
-- Schema shape (9 assertions) — dekt ALLE Constitution v1.0.1 precision claims
------------------------------------------------------------

select has_table('public', 'param_structurele_vermindering', 'param_structurele_vermindering table exists');
select has_table('public', 'param_doelgroepvermindering', 'param_doelgroepvermindering table exists');
select col_is_pk('public', 'param_structurele_vermindering', 'param_structurele_id', 'param_structurele_id is PK');
select col_is_pk('public', 'param_doelgroepvermindering', 'param_doelgroep_id', 'param_doelgroep_id is PK');
select col_type_is('public', 'param_structurele_vermindering', 'forfait', 'numeric(18,4)',
    'structurele.forfait is numeric(18,4) per Constitution v1.0.1 money precision');
select col_type_is('public', 'param_doelgroepvermindering', 'forfait', 'numeric(18,4)',
    'doelgroep.forfait is numeric(18,4) per Constitution v1.0.1 money precision');
select col_type_is('public', 'param_structurele_vermindering', 'coefficient_a', 'numeric(12,8)',
    'coefficient_a is numeric(12,8) per Constitution v1.0.1 dimensieloze coefficient (expliciet in precision-tabel)');
select col_type_is('public', 'param_structurele_vermindering', 'coefficient_b', 'numeric(12,8)',
    'coefficient_b is numeric(12,8) per Constitution v1.0.1 dimensieloze coefficient (expliciet in precision-tabel)');
select col_type_is('public', 'param_doelgroepvermindering', 'coefficient', 'numeric(12,8)',
    'doelgroep.coefficient is numeric(12,8) per Constitution v1.0.1 dimensieloze coefficient');


------------------------------------------------------------
-- NOT NULL smoke (8 assertions) — symmetric formula-parameter coverage
------------------------------------------------------------

select col_not_null('public', 'param_structurele_vermindering', 'werkgeverscategorie',
    'structurele.werkgeverscategorie NOT NULL');
select col_not_null('public', 'param_structurele_vermindering', 'forfait',
    'structurele.forfait NOT NULL');
select col_not_null('public', 'param_structurele_vermindering', 'coefficient_a',
    'structurele.coefficient_a NOT NULL (symmetric with coefficient_b per R = F - a*Delta - b*Delta formule)');
select col_not_null('public', 'param_structurele_vermindering', 'coefficient_b',
    'structurele.coefficient_b NOT NULL (symmetric with coefficient_a per R = F - a*Delta - b*Delta formule)');
select col_not_null('public', 'param_doelgroepvermindering', 'gewest',
    'doelgroep.gewest NOT NULL');
select col_not_null('public', 'param_doelgroepvermindering', 'doelgroep',
    'doelgroep.doelgroep NOT NULL');
select col_not_null('public', 'param_doelgroepvermindering', 'forfait',
    'doelgroep.forfait NOT NULL');
select col_not_null('public', 'param_doelgroepvermindering', 'coefficient',
    'doelgroep.coefficient NOT NULL');


------------------------------------------------------------
-- RLS role-scoped read: authenticated CAN read (2 assertions)
-- Seed 1 row per tabel als service_role, dan lezen als authenticated.
------------------------------------------------------------


-- Delete conflicting seed rows first (om exclusion constraint + unique periode
-- constraint te vermijden bij test insert).
delete from public.param_structurele_vermindering where werkgeverscategorie = 1;
insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url) values
    (1, '2024-01-01', '2025-01-01', 462.6000, 0.14200000, 0.00000000, 10797.67, 6807.18, 'https://www.socialsecurity.be/');

delete from public.param_doelgroepvermindering where gewest='vlaanderen' and doelgroep='oudere';
insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, voorwaarden_json, bron_url) values
    ('vlaanderen', 'oudere', '2024-01-01', '2025-01-01', 1500.0000, 0.00000000, '{"min_leeftijd":58}'::jsonb, 'https://www.vdab.be/');

reset role;

select tests.authenticate_as('test_reader');

-- Post fiscal audit: cat 1 has been deleted + reinserted (1 row), cat 2/3 seed
-- rijen blijven (2 stuks). Plus fiscal audit 2025 (6) + 2026 (3) = 12 rijen origineel,
-- min 1 delete + 1 test insert = 12 - 3 (cat1 uit 3 regimes) + 1 = 10.
select is(
    (select count(*)::int from public.param_structurele_vermindering),
    9,
    'authenticated reads param_structurele_vermindering — 9 rijen na cleanup + test insert'
);

-- Doelgroep: seed 6, minus 1 (vlaanderen oudere gedeleted) + 1 test insert = 6.
select is(
    (select count(*)::int from public.param_doelgroepvermindering),
    7,
    'authenticated reads param_doelgroepvermindering — 7 rijen na cleanup + test insert'
);


------------------------------------------------------------
-- RLS role-scoped read: anon CANNOT read (2 assertions)
------------------------------------------------------------

select tests.clear_authentication();
set local role anon;

select throws_ok(
    $$ select count(*) from public.param_structurele_vermindering $$,
    '42501',
    null,
    'anon SELECT param_structurele_vermindering → 42501'
);

select throws_ok(
    $$ select count(*) from public.param_doelgroepvermindering $$,
    '42501',
    null,
    'anon SELECT param_doelgroepvermindering → 42501'
);

reset role;


------------------------------------------------------------
-- REVOKE writes (2 assertions — explicit set local role authenticated)
------------------------------------------------------------

select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (2, '2024-01-01', 100.0000, 0.10000000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    '42501'
);

select throws_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, forfait, coefficient, bron_url)
       values ('brussel', 'jongere', '2024-01-01', 500.0000, 0.00000000, 'x') $$,
    '42501'
);


------------------------------------------------------------
-- gewest CHECK (1 assertion) — nederland is ongeldig
------------------------------------------------------------

select tests.clear_authentication();

select throws_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, forfait, coefficient, bron_url)
       values ('nederland', 'oudere', '2024-01-01', 1000.0000, 0.00000000, 'x') $$,
    '23514'
);


------------------------------------------------------------
-- werkgeverscategorie CHECK (1 assertion) — 4 is ongeldig
------------------------------------------------------------

select throws_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (4, '2024-01-01', 100.0000, 0.10000000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    '23514'
);


------------------------------------------------------------
-- Effective-dating CHECK — geldig_van < geldig_tot strict (4 assertions)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (2, '2024-06-01', '2024-01-01', 100.0000, 0.10000000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, bron_url)
       values ('wallonie', 'oudere', '2024-06-01', '2024-01-01', 500.0000, 0.00000000, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (2, '2024-06-01', '2024-06-01', 100.0000, 0.10000000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, bron_url)
       values ('wallonie', 'oudere', '2024-06-01', '2024-06-01', 500.0000, 0.00000000, 'x') $$,
    '23514'
);


------------------------------------------------------------
-- Exclusion constraint op param_structurele_vermindering (5 assertions)
------------------------------------------------------------

-- 1) Non-overlap same werkgeverscategorie
select lives_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (1, '2025-01-01', '2026-01-01', 470.0000, 0.14200000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    'non-overlapping periode allowed voor zelfde werkgeverscategorie'
);

-- 2) Overlap same werkgeverscategorie
select throws_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (1, '2024-06-01', '2025-06-01', 465.0000, 0.14200000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    '23P01'
);

-- 3) Cross-categorie disambiguation: same periode, different werkgeverscategorie
-- Delete cat 2 seed rijen om exclusion te vermijden.
delete from public.param_structurele_vermindering where werkgeverscategorie = 2;
select lives_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (2, '2024-01-01', '2025-01-01', 480.0000, 0.14200000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    'zelfde periode maar andere werkgeverscategorie: allowed (cross-categorie disambiguation)'
);

-- 4) Two open-ended (geldig_tot NULL) same werkgeverscategorie — delete seed cat 3 eerst.
delete from public.param_structurele_vermindering where werkgeverscategorie = 3;
insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
    values (3, '2024-01-01', null, 500.0000, 0.14200000, 0.00000000, 10797.67, 6807.18, 'x');

select throws_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (3, '2025-06-01', null, 510.0000, 0.14200000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    '23P01'
);

-- 5) Adjacent intervals (A.geldig_tot = B.geldig_van) — [) semantics
select lives_ok(
    $$ insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1, bron_url)
       values (1, '2026-01-01', '2027-01-01', 475.0000, 0.14200000, 0.00000000, 10797.67, 6807.18, 'x') $$,
    'adjacent [) intervals: allowed voor zelfde werkgeverscategorie'
);


------------------------------------------------------------
-- Exclusion constraint op param_doelgroepvermindering (5 assertions)
------------------------------------------------------------

-- 1) Non-overlap same (gewest, doelgroep)
select lives_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, bron_url)
       values ('vlaanderen', 'oudere', '2025-01-01', '2026-01-01', 1600.0000, 0.00000000, 'x') $$,
    'non-overlapping periode allowed voor zelfde (gewest, doelgroep)'
);

-- 2) Overlap same (gewest, doelgroep)
select throws_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, bron_url)
       values ('vlaanderen', 'oudere', '2024-06-01', '2025-06-01', 1550.0000, 0.00000000, 'x') $$,
    '23P01'
);

-- 3) Cross-gewest disambiguation: same periode + doelgroep, different gewest
select lives_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, bron_url)
       values ('wallonie', 'oudere', '2024-01-01', '2025-01-01', 1400.0000, 0.00000000, 'x') $$,
    'zelfde periode + doelgroep maar ander gewest: allowed (cross-gewest disambiguation)'
);

-- 4) Cross-doelgroep disambiguation: same periode + gewest, different doelgroep
-- Delete seed jongere_zonder_diploma vlaanderen om exclusion te vermijden.
delete from public.param_doelgroepvermindering where gewest='vlaanderen' and doelgroep='jongere_zonder_diploma';
select lives_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, bron_url)
       values ('vlaanderen', 'jongere_zonder_diploma', '2024-01-01', '2025-01-01', 1200.0000, 0.00000000, 'x') $$,
    'zelfde periode + gewest maar andere doelgroep: allowed (cross-doelgroep disambiguation)'
);

-- 5) Two open-ended (geldig_tot NULL) same (gewest, doelgroep)
insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, bron_url)
    values ('brussel', 'langdurig_werkloos', '2024-01-01', null, 1000.0000, 0.00000000, 'x');

select throws_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, bron_url)
       values ('brussel', 'langdurig_werkloos', '2025-06-01', null, 1100.0000, 0.00000000, 'x') $$,
    '23P01'
);


------------------------------------------------------------
-- voorwaarden_json handling (2 assertions — R3 fold-in)
------------------------------------------------------------

-- 1) Complexe nested jsonb accepted
select lives_ok(
    $$ insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, forfait, coefficient, voorwaarden_json, bron_url)
       values ('wallonie', 'langdurig_werkloos_50plus', '2024-01-01', 800.0000, 0.00000000,
               '{"min_leeftijd":50,"werkloos_min_maanden":12,"kwalificatie":"laaggeschoold"}'::jsonb, 'x') $$,
    'INSERT met complexe nested voorwaarden_json succeeds'
);

-- 2) DEFAULT '{}'::jsonb: omitted voorwaarden_json produces empty object
insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, forfait, coefficient, bron_url)
    values ('brussel', 'eerste_aanwerving', '2024-01-01', 1000.0000, 0.00000000, 'x');

select is(
    (select voorwaarden_json from public.param_doelgroepvermindering
     where gewest = 'brussel' and doelgroep = 'eerste_aanwerving' and geldig_van = '2024-01-01'),
    '{}'::jsonb,
    'omitted voorwaarden_json defaults to empty jsonb (DEFAULT contract for import scripts zonder filter-criteria)'
);

reset role;


select * from finish();
ROLLBACK;
