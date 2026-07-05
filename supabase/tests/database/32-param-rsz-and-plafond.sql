BEGIN;
create extension if not exists pgtap;

select plan(40);

select tests.create_supabase_user('test_reader');


------------------------------------------------------------
-- Schema shape (8 assertions) — includes precision coverage (EE2)
------------------------------------------------------------

select has_table('public', 'param_plafond', 'param_plafond table exists');
select has_table('public', 'param_rsz', 'param_rsz table exists');
select col_is_pk('public', 'param_plafond', 'param_plafond_id', 'param_plafond_id is PK');
select col_is_pk('public', 'param_rsz', 'param_rsz_id', 'param_rsz_id is PK');
select col_type_is('public', 'param_rsz', 'basisbijdrage_pct', 'numeric(6,4)',
    'basisbijdrage_pct is numeric(6,4) per Constitution v1.0.1');
select col_type_is('public', 'param_rsz', 'basisfactor_pct', 'numeric(6,4)',
    'basisfactor_pct is numeric(6,4) per Constitution v1.0.1 (EE2)');
select col_type_is('public', 'param_plafond', 'jaarplafond', 'numeric(18,4)',
    'jaarplafond is numeric(18,4) per Constitution v1.0.1 money precision (EE2)');
select col_type_is('public', 'param_plafond', 'kwartaalplafond', 'numeric(18,4)',
    'kwartaalplafond is numeric(18,4) per Constitution v1.0.1 money precision (EE2)');


------------------------------------------------------------
-- NOT NULL smoke tests (4 assertions — E7)
------------------------------------------------------------

select col_not_null('public', 'param_plafond', 'land_id', 'param_plafond.land_id NOT NULL');
select col_not_null('public', 'param_plafond', 'jaarplafond', 'param_plafond.jaarplafond NOT NULL');
select col_not_null('public', 'param_rsz', 'status', 'param_rsz.status NOT NULL');
select col_not_null('public', 'param_rsz', 'basisbijdrage_pct', 'param_rsz.basisbijdrage_pct NOT NULL');


------------------------------------------------------------
-- RLS role-scoped read: authenticated CAN read (2 assertions)
-- Seed one row per table as service_role, then read as authenticated.
------------------------------------------------------------


-- Unique test IDs voorkomen conflict met seed + 2024/2025 fiscal audit rijen.
insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url) values
    ('t32_cao90_test', 'BE', 'cao90', '2027-01-01', '2028-01-01', 4020.0000, 'https://www.socialsecurity.be/');

-- Delete 2025 open-ended om ruimte te maken voor 2027 test row (exclusion).
delete from public.param_rsz where status='bediende' and werkgeverscategorie=1 and geldig_van='2025-01-01';
insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url) values
    ('bediende', 1, '2027-01-01', '2028-01-01', 0.2540, 1.0000, 'https://www.socialsecurity.be/');


select tests.authenticate_as('test_reader');

-- Seed 2 + 1 test = 3 param_plafond; 12 seed - 1 delete + 1 test = 12 param_rsz.
select is(
    (select count(*)::int from public.param_plafond),
    3,
    'authenticated reads 3 param_plafond (2 seed 2025/2026 + 1 test row)'
);

select is(
    (select count(*)::int from public.param_rsz),
    12,
    'authenticated reads 12 param_rsz na seed - delete + test row'
);


------------------------------------------------------------
-- RLS role-scoped read: anon CANNOT read (2 assertions — S2)
-- Policy is `to authenticated`, so anon gets RLS-filtered 0 rows.
------------------------------------------------------------

select tests.clear_authentication();
set local role anon;

select throws_ok(
    $$ select count(*) from public.param_plafond $$,
    '42501',
    null,
    'anon SELECT param_plafond → 42501'
);

select throws_ok(
    $$ select count(*) from public.param_rsz $$,
    '42501',
    null,
    'anon SELECT param_rsz → 42501'
);

reset role;



------------------------------------------------------------
-- REVOKE writes (2 assertions — E8: explicit set local role authenticated)
------------------------------------------------------------

select tests.authenticate_as('test_reader');

select throws_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, jaarplafond, bron_url)
       values ('hack_2024', 'BE', 'hack', '2024-01-01', 1000.0000, 'x') $$,
    '42501'
);

select throws_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, basisbijdrage_pct, bron_url)
       values ('bediende', 1, '2024-01-01', 0.2540, 'x') $$,
    '42501'
);


------------------------------------------------------------
-- Biconditional CHECK on param_rsz.basisfactor_pct (4 assertions — E3)
-- Runs as service_role so REVOKE + RLS don't mask the CHECK.
------------------------------------------------------------

select tests.clear_authentication();

-- Post fiscal audit: basisfactor_pct is NOT NULL + range CHECK [1, 2].
-- De biconditional (bediende=NULL, arbeider=NOT NULL) uit T-015 is vervangen
-- door identity=1.0000 voor bediende, 1.0800 voor arbeider.

-- Failure paths (schema drift): NULL basisfactor_pct blokkeert bij BEIDE.
select throws_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('bediende', 2, '2029-01-01', 0.2540, null, 'x') $$,
    '23502'
);

-- Range CHECK: waarde buiten [1,2] faalt
select throws_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('arbeider', 2, '2029-01-01', 0.2540, 0.5, 'x') $$,
    '23514'
);

-- Success paths: delete existing 2025 open-ended eerst, dan test row.
delete from public.param_rsz where status='bediende' and werkgeverscategorie=2 and geldig_van='2025-01-01';
select lives_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('bediende', 2, '2030-01-01', 0.2540, 1.0000, 'x') $$,
    'bediende met basisfactor_pct 1.0000 identity toegestaan (post fiscal audit)'
);

delete from public.param_rsz where status='arbeider' and werkgeverscategorie=2 and geldig_van='2025-01-01';
select lives_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('arbeider', 2, '2030-01-01', 0.2540, 1.0800, 'x') $$,
    'arbeider met basisfactor_pct 1.08 toegestaan'
);


------------------------------------------------------------
-- Effective-dating CHECK — geldig_van < geldig_tot strict (3 assertions — E2 + E12 + E10)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('bediende', 1, '2024-06-01', '2024-01-01', 0.2540, 1.0000, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url)
       values ('bad_inv', 'BE', 'other', '2024-06-01', '2024-01-01', 1000.0000, 'x') $$,
    '23514'
);

select throws_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('bediende', 1, '2024-06-01', '2024-06-01', 0.2540, 1.0000, 'x') $$,
    '23514'
);


------------------------------------------------------------
-- Text PK regex CHECK on param_plafond (1 assertion — S5)
------------------------------------------------------------

select throws_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, jaarplafond, bron_url)
       values ('Bad Chars!', 'BE', 'other', '2024-01-01', 1000.0000, 'x') $$,
    '23514'
);


------------------------------------------------------------
-- Exclusion constraint on param_plafond (6 assertions — E1, E4, E10)
------------------------------------------------------------

-- 1) Non-overlapping rows same (land, bijdragetype) — allowed
select lives_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url)
       values ('cao90_jaar_2025', 'BE', 'cao90', '2025-01-01', '2026-01-01', 4100.0000, 'x') $$,
    'non-overlapping periode allowed voor zelfde (land, bijdragetype)'
);

-- 2) Overlapping same (land, bijdragetype) — blocked
select throws_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url)
       values ('cao90_overlap', 'BE', 'cao90', '2024-06-01', '2025-06-01', 4050.0000, 'x') $$,
    '23P01'
);

-- 3) Same period, different land_id — allowed (cross-country disambiguation E1)
select lives_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url)
       values ('cao90_de_2024', 'DE', 'cao90', '2024-01-01', '2025-01-01', 5000.0000, 'x') $$,
    'zelfde periode + bijdragetype maar ander land: allowed (cross-country E1)'
);

-- 4) Same period, different bijdragetype — allowed (cross-type disambiguation E1)
select lives_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url)
       values ('vin_wagen_2024', 'BE', 'vin_wagen', '2024-01-01', '2025-01-01', 6000.0000, 'x') $$,
    'zelfde periode + land maar ander bijdragetype: allowed (cross-type E1)'
);

-- 5) Two open-ended rows same (land, bijdragetype) — blocked (E4)
insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url)
    values ('open_ended_a', 'BE', 'openended_test', '2024-01-01', null, 100.0000, 'x');

select throws_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url)
       values ('open_ended_b', 'BE', 'openended_test', '2025-06-01', null, 100.0000, 'x') $$,
    '23P01'
);

-- 6) Adjacent intervals (A.geldig_tot = B.geldig_van, [) semantics) — allowed (E10)
select lives_ok(
    $$ insert into public.param_plafond (param_plafond_id, land_id, bijdragetype, geldig_van, geldig_tot, jaarplafond, bron_url)
       values ('cao90_be_2026', 'BE', 'cao90', '2026-01-01', '2027-01-01', 4200.0000, 'x') $$,
    'adjacent [) intervals: allowed (E10 semantics)'
);


------------------------------------------------------------
-- Exclusion constraint on param_rsz (5 assertions — E1, E4, EE5)
------------------------------------------------------------

-- Delete overlapping seed rows first (2024 + 2025 exclusion coverage).
delete from public.param_rsz where werkgeverscategorie in (1, 2, 3);

-- 1) Non-overlapping same (status, categorie) — allowed
select lives_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('bediende', 1, '2024-01-01', '2025-01-01', 0.2540, 1.0000, 'x') $$,
    'non-overlapping periode allowed voor zelfde (status, werkgeverscategorie)'
);

-- 2) Overlapping same (status, categorie) — blocked
select throws_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('bediende', 1, '2024-06-01', '2025-06-01', 0.2600, 1.0000, 'x') $$,
    '23P01'
);

-- 3) Same period, different status — allowed (cross-status disambiguation E1)
select lives_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('arbeider', 1, '2024-01-01', '2025-01-01', 0.2540, 1.0800, 'x') $$,
    'zelfde periode + categorie maar arbeider ipv bediende: allowed (cross-status E1)'
);

-- 4) Same period, different werkgeverscategorie — allowed (cross-cat disambiguation E1)
select lives_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('bediende', 2, '2024-06-01', '2025-01-01', 0.2555, 1.0000, 'x') $$,
    'zelfde periode + status maar andere werkgeverscategorie: allowed (cross-cat E1)'
);

-- 5) Two open-ended rows same (status, werkgeverscategorie) — blocked (EE5)
insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url)
    values ('bediende', 3, '2024-01-01', null, 0.2540, 1.0000, 'x');

select throws_ok(
    $$ insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url)
       values ('bediende', 3, '2025-06-01', null, 0.2540, 1.0000, 'x') $$,
    '23P01'
);


------------------------------------------------------------
-- dim_sz_behandeling FK — T-010 forward-ref voldoen (3 assertions — E5, E6)
------------------------------------------------------------

-- 1) Pre-check invariant: alle bestaande dim_sz_behandeling rijen hebben cap_param_plafond_id NULL (E5)
select is(
    (select count(*)::int from public.dim_sz_behandeling where cap_param_plafond_id is not null),
    0,
    'geen dim_sz_behandeling rijen met non-NULL cap_param_plafond_id vóór FK (E5 invariant)'
);

-- 2) Failure path: invalid cap_param_plafond_id → 23503 (foreign_key_violation)
select throws_ok(
    $$ insert into public.dim_sz_behandeling (sz_behandeling_id, regime_naam, grondslag_type, cap_param_plafond_id, bron_url)
       values ('bad_fk', 'Bad FK test', 'nvt', 'nonexistent_id', 'x') $$,
    '23503'
);

-- 3) Positive path: valid cap_param_plafond_id (uit seeded param_plafond) → success (E6)
select lives_ok(
    $$ insert into public.dim_sz_behandeling (sz_behandeling_id, regime_naam, grondslag_type, cap_param_plafond_id, bron_url)
       values ('valid_fk', 'Valid FK test', 'gunstig_tot_plafond', 't32_cao90_test', 'x') $$,
    'dim_sz_behandeling INSERT met valid cap_param_plafond_id succeeds (E6 positive-path)'
);



select * from finish();
ROLLBACK;
