BEGIN;
-- T-029: End-to-end integration test — cascade stap 1-7 tegen 3 scenarios.
-- POC subset: exact RSZ-brochure matches niet haalbaar (stap 5 zonder centenindex,
-- stap 6 zonder eindejaarspremie, stap 4 partial condition support). Assertions
-- verifiëren regressie-veiligheid, niet fiscale accuracy.
--
-- Scenarios:
--   A: bediende cat 1 PC 200, 32j hooggeschoold, bruto 4000, geen extras
--   B: arbeider cat 1 PC 124, 36j, bruto 3000
--   C: bediende cat 3 PC 200, 39j, bruto 5000 + groepsverzekering 1000

create extension "basejump-supabase_test_helpers" version '0.0.6';
select plan(13);

-- Setup
select tests.create_supabase_user('t');
select tests.authenticate_as('t');
insert into basejump.accounts (id, name, slug, personal_account) values ('a1111111-1111-1111-1111-111111111111', 'T', 'ts', false);
insert into public.dim_legale_entiteit (legale_entiteit_id, basejump_account_id, werkgeverscategorie, naam, land_id, gewest) values
    ('aaaaaaaa-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 1, 'A', 'BE', 'vlaanderen'),
    ('aaaaaaaa-1111-1111-1111-111111111112', 'a1111111-1111-1111-1111-111111111111', 1, 'B', 'BE', 'vlaanderen'),
    ('aaaaaaaa-1111-1111-1111-111111111113', 'a1111111-1111-1111-1111-111111111111', 3, 'C', 'BE', 'vlaanderen');
insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum, opleidingsniveau) values
    ('a2222222-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'v', '1992-01-01', 'hooggeschoold'),
    ('b2222222-1111-1111-1111-111111111112', 'a1111111-1111-1111-1111-111111111111', 'm', '1988-01-01', 'hooggeschoold'),
    ('c2222222-1111-1111-1111-111111111113', 'a1111111-1111-1111-1111-111111111111', 'v', '1985-01-01', 'hooggeschoold');
insert into public.dim_functie (functie_id, owning_account_id, functienaam) values ('f1000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'F');
insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van) values
    ('c1000000-0000-0000-0000-000000000001', 'a2222222-1111-1111-1111-111111111111', 'aaaaaaaa-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2023-01-01'),
    ('c2000000-0000-0000-0000-000000000002', 'b2222222-1111-1111-1111-111111111112', 'aaaaaaaa-1111-1111-1111-111111111112', 'f1000000-0000-0000-0000-000000000001', '124', 'arbeider', 1.0000, '2023-01-01'),
    ('c3000000-0000-0000-0000-000000000003', 'c2222222-1111-1111-1111-111111111113', 'aaaaaaaa-1111-1111-1111-111111111113', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2023-01-01');
insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind) values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-1111-1111-1111-111111111111', 'baseline', 'baseline');
insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values
    ('c1000000-0000-0000-0000-000000000001', '2024-06-01', 'basisloon', '11111111-1111-1111-1111-111111111111', 4000.0000),
    ('c2000000-0000-0000-0000-000000000002', '2024-06-01', 'basisloon', '11111111-1111-1111-1111-111111111111', 3000.0000),
    ('c3000000-0000-0000-0000-000000000003', '2024-06-01', 'basisloon', '11111111-1111-1111-1111-111111111111', 5000.0000),
    ('c3000000-0000-0000-0000-000000000003', '2024-06-01', 'groepsverzekering', '11111111-1111-1111-1111-111111111111', 1000.0000);

-- Scenario A: bediende cat 1
select is(public.cascade_stap1_rsz_grondslag('c1000000-0000-0000-0000-000000000001'::uuid, '2024-06-01'::date, '11111111-1111-1111-1111-111111111111'::uuid), 4000.0000::numeric(18,4), 'A1 stap1 grondslag');
select is(public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 1::smallint, '2024-06-01'::date), 1002.8000::numeric(18,4), 'A2 stap2 basis patronale');
select is(public.cascade_stap4_doelgroepverminderingen('c1000000-0000-0000-0000-000000000001'::uuid, 4000.0000, 1.0000, '2024-06-01'::date), 0.0000::numeric(18,4), 'A4 stap4 32j geen doelgroep');
select is(public.cascade_stap5_bijzondere_bijdragen(4000.0000, '2024-06-01'::date), 320.8000::numeric(18,4), 'A5 stap5 bijzondere bijdragen');
select is(public.cascade_stap6_vakantiegeld(4000.0000, 'bediende', '2024-06-01'::date), 3986.8000::numeric(18,4), 'A6 stap6 vakantiegeld bediende');
select is(public.cascade_stap7_extralegaal('c1000000-0000-0000-0000-000000000001'::uuid, '2024-06-01'::date, '11111111-1111-1111-1111-111111111111'::uuid), 0.0000::numeric(18,4), 'A7 stap7 geen extralegaal');

-- Scenario B: arbeider cat 1
select is(public.cascade_stap1_rsz_grondslag('c2000000-0000-0000-0000-000000000002'::uuid, '2024-06-01'::date, '11111111-1111-1111-1111-111111111111'::uuid), 3000.0000::numeric(18,4), 'B1 stap1 arbeider');
select is(public.cascade_stap2_basis_patronale_rsz(3000.0000, 'arbeider', 1::smallint, '2024-06-01'::date), 812.2680::numeric(18,4), 'B2 stap2 arbeider basisfactor 1.08');
select is(public.cascade_stap5_bijzondere_bijdragen(3000.0000, '2024-06-01'::date), 240.6000::numeric(18,4), 'B5 stap5 arbeider');
select is(public.cascade_stap6_vakantiegeld(3000.0000, 'arbeider', '2024-06-01'::date), 461.4000::numeric(18,4), 'B6 stap6 arbeider vakantiegeld 15.38%');

-- Scenario C: bediende cat 3 met groepsverzekering
select is(public.cascade_stap1_rsz_grondslag('c3000000-0000-0000-0000-000000000003'::uuid, '2024-06-01'::date, '11111111-1111-1111-1111-111111111111'::uuid), 5000.0000::numeric(18,4), 'C1 stap1 basisloon (groepsverzekering NIET rsz_plichtig)');
select is(public.cascade_stap7_extralegaal('c3000000-0000-0000-0000-000000000003'::uuid, '2024-06-01'::date, '11111111-1111-1111-1111-111111111111'::uuid), 132.6000::numeric(18,4), 'C7 stap7 groepsverzekering 1000 × 0.1326');

-- End-to-end sum (approximation for scenario A): stap 2 + stap 5 + stap 6 = patronale kost
select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 1::smallint, '2024-06-01'::date)
    + public.cascade_stap5_bijzondere_bijdragen(4000.0000, '2024-06-01'::date)
    + public.cascade_stap6_vakantiegeld(4000.0000, 'bediende', '2024-06-01'::date),
    5310.4000::numeric(18,4),
    'Scenario A end-to-end patronale kost = stap2 + stap5 + stap6 = 5310.40 (excl. stap 3/4/7 which zero)'
);

select * from finish();
ROLLBACK;
