BEGIN;
-- Depends on dim_pc seed rows: 111, 124, 200, 302 (see supabase/migrations/20260703020000_dim_pc.sql).
-- Als dim_pc seed IDs herbenoemd worden, faalt deze test suite als indicator van cross-migration coupling.

create extension if not exists pgtap;

select plan(139);

select tests.create_supabase_user('test_reader');


------------------------------------------------------------
------------------------------------------------------------
-- 1) param_arbeidsduur (18 assertions)
------------------------------------------------------------
------------------------------------------------------------

-- Schema shape (3 assertions)
select has_table('public', 'param_arbeidsduur', 'param_arbeidsduur table exists');
select col_is_pk('public', 'param_arbeidsduur', 'param_arbeidsduur_id', 'param_arbeidsduur_id is PK');
select col_type_is('public', 'param_arbeidsduur', 'gemiddelde_wekelijkse_uren', 'numeric(6,4)',
    'gemiddelde_wekelijkse_uren is numeric(6,4) per Constitution v1.0.1 breuk precision');

-- NOT NULL smoke (4 assertions)
select col_not_null('public', 'param_arbeidsduur', 'pc_id',
    'arbeidsduur.pc_id NOT NULL');
select col_not_null('public', 'param_arbeidsduur', 'geldig_van',
    'arbeidsduur.geldig_van NOT NULL');
select col_not_null('public', 'param_arbeidsduur', 'gemiddelde_wekelijkse_uren',
    'arbeidsduur.gemiddelde_wekelijkse_uren NOT NULL');
select col_not_null('public', 'param_arbeidsduur', 'bron_url',
    'arbeidsduur.bron_url NOT NULL');

-- RLS role-scoped read: authenticated CAN read + anon CANNOT read (2 assertions)
set local role service_role;

insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url) values
    ('200', '2024-01-01', '2025-01-01', 38.0000, 'https://werk.belgie.be/');

reset role;

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.param_arbeidsduur),
    1,
    'authenticated user reads param_arbeidsduur (global read via to authenticated policy)'
);

select tests.clear_authentication();
set local role anon;

select is(
    (select count(*)::int from public.param_arbeidsduur),
    0,
    'anon reads 0 rows from param_arbeidsduur (RLS blocks via to authenticated policy)'
);

reset role;

-- REVOKE writes (1 assertion)
select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, gemiddelde_wekelijkse_uren, bron_url)
       values ('200', '2024-01-01', 38.0000, 'x') $$,
    '42501'
);

-- Effective-dating CHECK: inversion + boundary (2 assertions)
select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url)
       values ('200', '2024-06-01', '2024-01-01', 38.0000, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url)
       values ('200', '2024-06-01', '2024-06-01', 38.0000, 'x') $$,
    '23514'
);

-- Exclusion constraint (3 assertions: non-overlap, overlap, open-ended)
select lives_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url)
       values ('200', '2025-01-01', '2026-01-01', 38.0000, 'x') $$,
    'non-overlapping periode allowed voor zelfde pc_id'
);

select throws_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url)
       values ('200', '2024-06-01', '2025-06-01', 38.0000, 'x') $$,
    '23P01'
);

insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url)
    values ('124', '2024-01-01', null, 40.0000, 'x');

select throws_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url)
       values ('124', '2025-06-01', null, 40.0000, 'x') $$,
    '23P01'
);

-- Cross-pc disambiguation (1 assertion)
select lives_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url)
       values ('302', '2024-01-01', '2025-01-01', 38.0000, 'x') $$,
    'zelfde periode maar andere pc_id: allowed (cross-pc disambiguation)'
);

-- FK invalid + FK positive (2 assertions)
select throws_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, gemiddelde_wekelijkse_uren, bron_url)
       values ('nonexistent_pc', '2027-01-01', 38.0000, 'x') $$,
    '23503'
);

select lives_ok(
    $$ insert into public.param_arbeidsduur (pc_id, geldig_van, gemiddelde_wekelijkse_uren, bron_url)
       values ('111', '2027-01-01', 38.0000, 'x') $$,
    'FK positive path: valid pc_id 111 accepted'
);

reset role;


------------------------------------------------------------
------------------------------------------------------------
-- 2) param_vakantiegeld (19 assertions)
------------------------------------------------------------
------------------------------------------------------------

-- Schema shape (4 assertions)
select has_table('public', 'param_vakantiegeld', 'param_vakantiegeld table exists');
select col_is_pk('public', 'param_vakantiegeld', 'param_vakantiegeld_id', 'param_vakantiegeld_id is PK');
select col_type_is('public', 'param_vakantiegeld', 'enkel_pct', 'numeric(6,4)',
    'enkel_pct is numeric(6,4) per Constitution v1.0.1 percentage precision');
select col_type_is('public', 'param_vakantiegeld', 'dubbel_pct', 'numeric(6,4)',
    'dubbel_pct is numeric(6,4) per Constitution v1.0.1 percentage precision');

-- NOT NULL smoke (5 assertions)
select col_not_null('public', 'param_vakantiegeld', 'regime',
    'vakantiegeld.regime NOT NULL');
select col_not_null('public', 'param_vakantiegeld', 'geldig_van',
    'vakantiegeld.geldig_van NOT NULL');
select col_not_null('public', 'param_vakantiegeld', 'enkel_pct',
    'vakantiegeld.enkel_pct NOT NULL');
select col_not_null('public', 'param_vakantiegeld', 'dubbel_pct',
    'vakantiegeld.dubbel_pct NOT NULL');
select col_not_null('public', 'param_vakantiegeld', 'bron_url',
    'vakantiegeld.bron_url NOT NULL');

-- RLS role-scoped read: authenticated CAN read + anon CANNOT read (2 assertions)
set local role service_role;

insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url) values
    ('arbeider', '2024-01-01', '2025-01-01', 15.3800, 92.0000, 'https://www.rjv.be/');

reset role;

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.param_vakantiegeld),
    1,
    'authenticated user reads param_vakantiegeld (global read via to authenticated policy)'
);

select tests.clear_authentication();
set local role anon;

select is(
    (select count(*)::int from public.param_vakantiegeld),
    0,
    'anon reads 0 rows from param_vakantiegeld (RLS blocks via to authenticated policy)'
);

reset role;

-- REVOKE writes (1 assertion)
select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_vakantiegeld (regime, geldig_van, enkel_pct, dubbel_pct, bron_url)
       values ('bediende', '2024-01-01', 8.0000, 92.0000, 'x') $$,
    '42501'
);

-- regime CHECK negative (1 assertion)
select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.param_vakantiegeld (regime, geldig_van, enkel_pct, dubbel_pct, bron_url)
       values ('freelancer', '2024-01-01', 8.0000, 92.0000, 'x') $$,
    '23514'
);

-- Effective-dating CHECK: inversion + boundary (2 assertions)
select throws_ok(
    $$ insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url)
       values ('bediende', '2024-06-01', '2024-01-01', 8.0000, 92.0000, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url)
       values ('bediende', '2024-06-01', '2024-06-01', 8.0000, 92.0000, 'x') $$,
    '23514'
);

-- Exclusion constraint (3 assertions: non-overlap, overlap, open-ended)
select lives_ok(
    $$ insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url)
       values ('arbeider', '2025-01-01', '2026-01-01', 15.3800, 92.0000, 'x') $$,
    'non-overlapping periode allowed voor zelfde regime'
);

select throws_ok(
    $$ insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url)
       values ('arbeider', '2024-06-01', '2025-06-01', 15.3800, 92.0000, 'x') $$,
    '23P01'
);

insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url)
    values ('bediende', '2024-01-01', null, 8.0000, 92.0000, 'x');

select throws_ok(
    $$ insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url)
       values ('bediende', '2025-06-01', null, 8.0000, 92.0000, 'x') $$,
    '23P01'
);

-- Cross-regime disambiguation (1 assertion)
select lives_ok(
    $$ insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url)
       values ('bediende', '2026-01-01', '2027-01-01', 8.0000, 92.0000, 'x') $$,
    'ander regime + andere periode: allowed'
);

reset role;


------------------------------------------------------------
------------------------------------------------------------
-- 3) param_index (20 assertions)
------------------------------------------------------------
------------------------------------------------------------

-- Schema shape (4 assertions)
select has_table('public', 'param_index', 'param_index table exists');
select col_is_pk('public', 'param_index', 'param_index_id', 'param_index_id is PK');
select col_type_is('public', 'param_index', 'index_coefficient', 'numeric(10,6)',
    'index_coefficient is numeric(10,6) per Constitution v1.0.1 EXPLICIT precision claim');
select col_type_is('public', 'param_index', 'drempel_bruto', 'numeric(18,4)',
    'drempel_bruto is numeric(18,4) per Constitution v1.0.1 money precision');

-- NOT NULL smoke (5 assertions)
select col_not_null('public', 'param_index', 'pc_id',
    'index.pc_id NOT NULL');
select col_not_null('public', 'param_index', 'geldig_van',
    'index.geldig_van NOT NULL');
select col_not_null('public', 'param_index', 'index_coefficient',
    'index.index_coefficient NOT NULL');
select col_not_null('public', 'param_index', 'drempel_bruto',
    'index.drempel_bruto NOT NULL');
select col_not_null('public', 'param_index', 'bron_url',
    'index.bron_url NOT NULL');

-- RLS role-scoped read: authenticated CAN read + anon CANNOT read (2 assertions)
set local role service_role;

insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url) values
    ('200', '2024-01-01', '2025-01-01', 1.020000, 4000.0000, 'https://statbel.fgov.be/');

reset role;

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.param_index),
    1,
    'authenticated user reads param_index (global read via to authenticated policy)'
);

select tests.clear_authentication();
set local role anon;

select is(
    (select count(*)::int from public.param_index),
    0,
    'anon reads 0 rows from param_index (RLS blocks via to authenticated policy)'
);

reset role;

-- REVOKE writes (1 assertion)
select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_index (pc_id, geldig_van, index_coefficient, drempel_bruto, bron_url)
       values ('200', '2024-01-01', 1.020000, 4000.0000, 'x') $$,
    '42501'
);

-- Effective-dating CHECK: inversion + boundary (2 assertions)
select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url)
       values ('200', '2024-06-01', '2024-01-01', 1.020000, 4000.0000, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url)
       values ('200', '2024-06-01', '2024-06-01', 1.020000, 4000.0000, 'x') $$,
    '23514'
);

-- Exclusion constraint (3 assertions: non-overlap, overlap, open-ended)
select lives_ok(
    $$ insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url)
       values ('200', '2025-01-01', '2026-01-01', 1.030000, 4000.0000, 'x') $$,
    'non-overlapping periode allowed voor zelfde pc_id'
);

select throws_ok(
    $$ insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url)
       values ('200', '2024-06-01', '2025-06-01', 1.020000, 4000.0000, 'x') $$,
    '23P01'
);

insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url)
    values ('124', '2024-01-01', null, 1.020000, 4000.0000, 'x');

select throws_ok(
    $$ insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url)
       values ('124', '2025-06-01', null, 1.020000, 4000.0000, 'x') $$,
    '23P01'
);

-- Cross-pc disambiguation (1 assertion)
select lives_ok(
    $$ insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url)
       values ('302', '2024-01-01', '2025-01-01', 1.020000, 4000.0000, 'x') $$,
    'zelfde periode maar andere pc_id: allowed (cross-pc disambiguation)'
);

-- FK invalid + FK positive (2 assertions)
select throws_ok(
    $$ insert into public.param_index (pc_id, geldig_van, index_coefficient, drempel_bruto, bron_url)
       values ('nonexistent_pc', '2027-01-01', 1.020000, 4000.0000, 'x') $$,
    '23503'
);

select lives_ok(
    $$ insert into public.param_index (pc_id, geldig_van, index_coefficient, drempel_bruto, bron_url)
       values ('111', '2027-01-01', 1.020000, 4000.0000, 'x') $$,
    'FK positive path: valid pc_id 111 accepted'
);

reset role;


------------------------------------------------------------
------------------------------------------------------------
-- 4) param_bijzondere_bijdragen (20 assertions)
------------------------------------------------------------
------------------------------------------------------------

-- Schema shape (3 assertions)
select has_table('public', 'param_bijzondere_bijdragen', 'param_bijzondere_bijdragen table exists');
select col_is_pk('public', 'param_bijzondere_bijdragen', 'param_bijzondere_bijdragen_id', 'param_bijzondere_bijdragen_id is PK');
select col_type_is('public', 'param_bijzondere_bijdragen', 'tarief', 'numeric(6,4)',
    'tarief is numeric(6,4) per Constitution v1.0.1 percentage precision');

-- NOT NULL smoke (5 assertions)
select col_not_null('public', 'param_bijzondere_bijdragen', 'type',
    'bijzondere_bijdragen.type NOT NULL');
select col_not_null('public', 'param_bijzondere_bijdragen', 'geldig_van',
    'bijzondere_bijdragen.geldig_van NOT NULL');
select col_not_null('public', 'param_bijzondere_bijdragen', 'tarief',
    'bijzondere_bijdragen.tarief NOT NULL');
select col_not_null('public', 'param_bijzondere_bijdragen', 'formule_json',
    'bijzondere_bijdragen.formule_json NOT NULL');
select col_not_null('public', 'param_bijzondere_bijdragen', 'bron_url',
    'bijzondere_bijdragen.bron_url NOT NULL');

-- RLS role-scoped read: authenticated CAN read + anon CANNOT read (2 assertions)
set local role service_role;

insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, formule_json, bron_url) values
    ('loonmatiging', '2024-01-01', '2025-01-01', 0.5000, '{"formule":"0.5 * indexbesparing"}'::jsonb, 'https://www.socialsecurity.be/');

reset role;

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.param_bijzondere_bijdragen),
    1,
    'authenticated user reads param_bijzondere_bijdragen (global read via to authenticated policy)'
);

select tests.clear_authentication();
set local role anon;

select is(
    (select count(*)::int from public.param_bijzondere_bijdragen),
    0,
    'anon reads 0 rows from param_bijzondere_bijdragen (RLS blocks via to authenticated policy)'
);

reset role;

-- REVOKE writes (1 assertion)
select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, tarief, bron_url)
       values ('fso', '2024-01-01', 0.0100, 'x') $$,
    '42501'
);

-- type CHECK negative (1 assertion)
select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, tarief, bron_url)
       values ('onbekend_type', '2024-01-01', 0.0100, 'x') $$,
    '23514'
);

-- Effective-dating CHECK: inversion + boundary (2 assertions)
select throws_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, bron_url)
       values ('fso', '2024-06-01', '2024-01-01', 0.0100, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, bron_url)
       values ('fso', '2024-06-01', '2024-06-01', 0.0100, 'x') $$,
    '23514'
);

-- Exclusion constraint (3 assertions: non-overlap, overlap, open-ended)
select lives_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, bron_url)
       values ('loonmatiging', '2025-01-01', '2026-01-01', 0.5000, 'x') $$,
    'non-overlapping periode allowed voor zelfde type'
);

select throws_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, bron_url)
       values ('loonmatiging', '2024-06-01', '2025-06-01', 0.5000, 'x') $$,
    '23P01'
);

insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, bron_url)
    values ('asbest', '2024-01-01', null, 0.0100, 'x');

select throws_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, bron_url)
       values ('asbest', '2025-06-01', null, 0.0100, 'x') $$,
    '23P01'
);

-- Cross-type disambiguation (1 assertion)
select lives_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, bron_url)
       values ('bev', '2024-01-01', '2025-01-01', 0.0100, 'x') $$,
    'zelfde periode maar ander type: allowed (cross-type disambiguation)'
);

-- jsonb: nested lives_ok + DEFAULT '{}' behavior (2 assertions)
select lives_ok(
    $$ insert into public.param_bijzondere_bijdragen (type, geldig_van, tarief, formule_json, bron_url)
       values ('fso', '2027-01-01', 0.0100, '{"basis":"brutoloon_wettelijk","factor":0.5,"nested":{"a":1,"b":2}}'::jsonb, 'x') $$,
    'INSERT met complexe nested formule_json succeeds'
);

insert into public.param_bijzondere_bijdragen (type, geldig_van, tarief, bron_url)
    values ('bev', '2027-01-01', 0.0100, 'x');

select is(
    (select formule_json from public.param_bijzondere_bijdragen
     where type = 'bev' and geldig_van = '2027-01-01'),
    '{}'::jsonb,
    'omitted formule_json defaults to empty jsonb (DEFAULT contract for import scripts)'
);

reset role;


------------------------------------------------------------
------------------------------------------------------------
-- 5) param_sectorbijdrage (21 assertions)
------------------------------------------------------------
------------------------------------------------------------

-- Schema shape (3 assertions)
select has_table('public', 'param_sectorbijdrage', 'param_sectorbijdrage table exists');
select col_is_pk('public', 'param_sectorbijdrage', 'param_sectorbijdrage_id', 'param_sectorbijdrage_id is PK');
select col_type_is('public', 'param_sectorbijdrage', 'tarief', 'numeric(6,4)',
    'tarief is numeric(6,4) per Constitution v1.0.1 percentage precision');

-- NOT NULL smoke (5 assertions)
select col_not_null('public', 'param_sectorbijdrage', 'pc_id',
    'sectorbijdrage.pc_id NOT NULL');
select col_not_null('public', 'param_sectorbijdrage', 'fonds',
    'sectorbijdrage.fonds NOT NULL');
select col_not_null('public', 'param_sectorbijdrage', 'geldig_van',
    'sectorbijdrage.geldig_van NOT NULL');
select col_not_null('public', 'param_sectorbijdrage', 'tarief',
    'sectorbijdrage.tarief NOT NULL');
select col_not_null('public', 'param_sectorbijdrage', 'bron_url',
    'sectorbijdrage.bron_url NOT NULL');

-- RLS role-scoped read: authenticated CAN read + anon CANNOT read (2 assertions)
set local role service_role;

insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url) values
    ('200', 'bestaanszekerheid', '2024-01-01', '2025-01-01', 0.0100, 'https://www.socialsecurity.be/');

reset role;

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.param_sectorbijdrage),
    1,
    'authenticated user reads param_sectorbijdrage (global read via to authenticated policy)'
);

select tests.clear_authentication();
set local role anon;

select is(
    (select count(*)::int from public.param_sectorbijdrage),
    0,
    'anon reads 0 rows from param_sectorbijdrage (RLS blocks via to authenticated policy)'
);

reset role;

-- REVOKE writes (1 assertion)
select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, tarief, bron_url)
       values ('200', 'vorming', '2024-01-01', 0.0100, 'x') $$,
    '42501'
);

-- Effective-dating CHECK: inversion + boundary (2 assertions)
select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url)
       values ('200', 'vorming', '2024-06-01', '2024-01-01', 0.0100, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url)
       values ('200', 'vorming', '2024-06-01', '2024-06-01', 0.0100, 'x') $$,
    '23514'
);

-- Exclusion constraint (3 assertions: non-overlap, overlap, open-ended)
select lives_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url)
       values ('200', 'bestaanszekerheid', '2025-01-01', '2026-01-01', 0.0100, 'x') $$,
    'non-overlapping periode allowed voor zelfde (pc_id, fonds)'
);

select throws_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url)
       values ('200', 'bestaanszekerheid', '2024-06-01', '2025-06-01', 0.0100, 'x') $$,
    '23P01'
);

insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url)
    values ('124', 'risicogroepen', '2024-01-01', null, 0.0100, 'x');

select throws_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url)
       values ('124', 'risicogroepen', '2025-06-01', null, 0.0100, 'x') $$,
    '23P01'
);

-- Cross-pc disambiguation (1 assertion)
select lives_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url)
       values ('302', 'bestaanszekerheid', '2024-01-01', '2025-01-01', 0.0100, 'x') $$,
    'zelfde periode + fonds maar andere pc_id: allowed (cross-pc disambiguation)'
);

-- Cross-fonds disambiguation (1 assertion)
select lives_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url)
       values ('200', 'vorming', '2024-01-01', '2025-01-01', 0.0100, 'x') $$,
    'zelfde periode + pc_id maar ander fonds: allowed (cross-fonds disambiguation)'
);

-- FK invalid + FK positive (2 assertions)
select throws_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, tarief, bron_url)
       values ('nonexistent_pc', 'bestaanszekerheid', '2027-01-01', 0.0100, 'x') $$,
    '23503'
);

select lives_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, tarief, bron_url)
       values ('111', 'bestaanszekerheid', '2027-01-01', 0.0100, 'x') $$,
    'FK positive path: valid pc_id 111 accepted'
);

-- Regex CHECK negative op fonds (1 assertion)
select throws_ok(
    $$ insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, tarief, bron_url)
       values ('200', 'Bad Chars!', '2028-01-01', 0.0100, 'x') $$,
    '23514'
);

reset role;


------------------------------------------------------------
------------------------------------------------------------
-- 6) param_extralegaal (19 assertions)
------------------------------------------------------------
------------------------------------------------------------

-- Schema shape (4 assertions)
select has_table('public', 'param_extralegaal', 'param_extralegaal table exists');
select col_is_pk('public', 'param_extralegaal', 'param_extralegaal_id', 'param_extralegaal_id is PK');
select col_type_is('public', 'param_extralegaal', 'max_wg', 'numeric(18,4)',
    'max_wg is numeric(18,4) per Constitution v1.0.1 money precision');
select col_type_is('public', 'param_extralegaal', 'taks_pct', 'numeric(6,4)',
    'taks_pct is numeric(6,4) per Constitution v1.0.1 percentage precision');

-- NOT NULL smoke (5 assertions)
select col_not_null('public', 'param_extralegaal', 'voordeeltype',
    'extralegaal.voordeeltype NOT NULL');
select col_not_null('public', 'param_extralegaal', 'geldig_van',
    'extralegaal.geldig_van NOT NULL');
select col_not_null('public', 'param_extralegaal', 'max_wg',
    'extralegaal.max_wg NOT NULL');
select col_not_null('public', 'param_extralegaal', 'taks_pct',
    'extralegaal.taks_pct NOT NULL');
select col_not_null('public', 'param_extralegaal', 'bron_url',
    'extralegaal.bron_url NOT NULL');

-- RLS role-scoped read: authenticated CAN read + anon CANNOT read (2 assertions)
set local role service_role;

insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url) values
    ('chequegrenzen', '2024-01-01', '2025-01-01', 7.0000, 0.0000, 'https://www.rsz.fgov.be/');

reset role;

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.param_extralegaal),
    1,
    'authenticated user reads param_extralegaal (global read via to authenticated policy)'
);

select tests.clear_authentication();
set local role anon;

select is(
    (select count(*)::int from public.param_extralegaal),
    0,
    'anon reads 0 rows from param_extralegaal (RLS blocks via to authenticated policy)'
);

reset role;

-- REVOKE writes (1 assertion)
select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_extralegaal (voordeeltype, geldig_van, max_wg, taks_pct, bron_url)
       values ('groepsverzekering', '2024-01-01', 0.0000, 8.8600, 'x') $$,
    '42501'
);

-- Effective-dating CHECK: inversion + boundary (2 assertions)
select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url)
       values ('groepsverzekering', '2024-06-01', '2024-01-01', 0.0000, 8.8600, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url)
       values ('groepsverzekering', '2024-06-01', '2024-06-01', 0.0000, 8.8600, 'x') $$,
    '23514'
);

-- Exclusion constraint (3 assertions: non-overlap, overlap, open-ended)
select lives_ok(
    $$ insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url)
       values ('chequegrenzen', '2025-01-01', '2026-01-01', 7.0000, 0.0000, 'x') $$,
    'non-overlapping periode allowed voor zelfde voordeeltype'
);

select throws_ok(
    $$ insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url)
       values ('chequegrenzen', '2024-06-01', '2025-06-01', 7.0000, 0.0000, 'x') $$,
    '23P01'
);

insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url)
    values ('mobiliteitsbudget', '2024-01-01', null, 0.0000, 0.0000, 'x');

select throws_ok(
    $$ insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url)
       values ('mobiliteitsbudget', '2025-06-01', null, 0.0000, 0.0000, 'x') $$,
    '23P01'
);

-- Cross-voordeeltype disambiguation (1 assertion)
select lives_ok(
    $$ insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url)
       values ('groepsverzekering', '2024-01-01', '2025-01-01', 0.0000, 8.8600, 'x') $$,
    'zelfde periode maar ander voordeeltype: allowed (cross-voordeeltype disambiguation)'
);

-- Regex CHECK negative op voordeeltype (1 assertion)
select throws_ok(
    $$ insert into public.param_extralegaal (voordeeltype, geldig_van, max_wg, taks_pct, bron_url)
       values ('Bad Chars!', '2028-01-01', 0.0000, 0.0000, 'x') $$,
    '23514'
);

reset role;


------------------------------------------------------------
------------------------------------------------------------
-- 7) param_wagen_mobiliteit (21 assertions)
------------------------------------------------------------
------------------------------------------------------------

-- Schema shape (4 assertions)
select has_table('public', 'param_wagen_mobiliteit', 'param_wagen_mobiliteit table exists');
select col_is_pk('public', 'param_wagen_mobiliteit', 'param_wagen_mobiliteit_id', 'param_wagen_mobiliteit_id is PK');
select col_type_is('public', 'param_wagen_mobiliteit', 'minimumbijdrage', 'numeric(18,4)',
    'minimumbijdrage is numeric(18,4) per Constitution v1.0.1 money precision');
select col_type_is('public', 'param_wagen_mobiliteit', 'vaa_coefficient', 'numeric(12,8)',
    'vaa_coefficient is numeric(12,8) per Constitution v1.0.1 dimensieloze coefficient');

-- NOT NULL smoke (6 assertions)
select col_not_null('public', 'param_wagen_mobiliteit', 'geldig_van',
    'wagen_mobiliteit.geldig_van NOT NULL');
select col_not_null('public', 'param_wagen_mobiliteit', 'co2_formule_json',
    'wagen_mobiliteit.co2_formule_json NOT NULL');
select col_not_null('public', 'param_wagen_mobiliteit', 'referentie_co2',
    'wagen_mobiliteit.referentie_co2 NOT NULL');
select col_not_null('public', 'param_wagen_mobiliteit', 'minimumbijdrage',
    'wagen_mobiliteit.minimumbijdrage NOT NULL');
select col_not_null('public', 'param_wagen_mobiliteit', 'vaa_coefficient',
    'wagen_mobiliteit.vaa_coefficient NOT NULL');
select col_not_null('public', 'param_wagen_mobiliteit', 'bron_url',
    'wagen_mobiliteit.bron_url NOT NULL');

-- RLS role-scoped read: authenticated CAN read + anon CANNOT read (2 assertions)
set local role service_role;

insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, co2_formule_json, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url) values
    ('2024-01-01', '2025-01-01', '{"formule":"((co2 - referentie) * factor + basis) / 12","factor":9.0}'::jsonb, 91, 31.9900, 1.00000000, 'https://www.socialsecurity.be/');

reset role;

select tests.authenticate_as('test_reader');

select is(
    (select count(*)::int from public.param_wagen_mobiliteit),
    1,
    'authenticated user reads param_wagen_mobiliteit (global read via to authenticated policy)'
);

select tests.clear_authentication();
set local role anon;

select is(
    (select count(*)::int from public.param_wagen_mobiliteit),
    0,
    'anon reads 0 rows from param_wagen_mobiliteit (RLS blocks via to authenticated policy)'
);

reset role;

-- REVOKE writes (1 assertion)
select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2024-01-01', 91, 31.9900, 1.00000000, 'x') $$,
    '42501'
);

-- Effective-dating CHECK: inversion + boundary (2 assertions)
select tests.clear_authentication();
set local role service_role;

select throws_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2024-06-01', '2024-01-01', 91, 31.9900, 1.00000000, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2024-06-01', '2024-06-01', 91, 31.9900, 1.00000000, 'x') $$,
    '23514'
);

-- Exclusion constraint single-key (3 assertions: non-overlap, overlap, two open-ended)
select lives_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2025-01-01', '2026-01-01', 91, 31.9900, 1.00000000, 'x') $$,
    'non-overlapping periode allowed (single-key exclusion op daterange)'
);

select throws_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2024-06-01', '2025-06-01', 91, 31.9900, 1.00000000, 'x') $$,
    '23P01'
);

-- Two open-ended (geldig_tot NULL) op single-key exclusion — 23P01.
-- Reset state met delete: single-key exclusion (alleen daterange, geen discriminator)
-- betekent dat elke geldige eerder-geïnserte row ook 'infinity'-range zou raken. Principe I
-- test is dat 2 open-ended rows onmogelijk zijn, niet dat delete er niet werkt — de delete
-- staat binnen BEGIN/ROLLBACK van de test-transactie en heeft geen invloed op andere sessies.
delete from public.param_wagen_mobiliteit;
insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
    values ('2020-01-01', null, 91, 31.9900, 1.00000000, 'x');

select throws_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2022-01-01', null, 91, 31.9900, 1.00000000, 'x') $$,
    '23P01'
);

-- jsonb: nested lives_ok + DEFAULT '{}' behavior (2 assertions)
select lives_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, co2_formule_json, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2027-01-01', '2028-01-01', '{"formule":"complex","factor":9.0,"nested":{"a":1,"b":{"c":2}}}'::jsonb, 91, 31.9900, 1.00000000, 'x') $$,
    'INSERT met complexe nested co2_formule_json succeeds'
);

insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
    values ('2028-01-01', '2029-01-01', 91, 31.9900, 1.00000000, 'x');

select is(
    (select co2_formule_json from public.param_wagen_mobiliteit
     where geldig_van = '2028-01-01' and geldig_tot = '2029-01-01'),
    '{}'::jsonb,
    'omitted co2_formule_json defaults to empty jsonb (DEFAULT contract for import scripts)'
);

-- CO2 range CHECK negative (2 assertions) — waarde 40 < 50 en 401 > 400 → 23514
select throws_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2029-06-01', '2030-01-01', 40, 31.9900, 1.00000000, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url)
       values ('2029-06-01', '2030-01-01', 401, 31.9900, 1.00000000, 'x') $$,
    '23514'
);

reset role;


select * from finish();
ROLLBACK;
