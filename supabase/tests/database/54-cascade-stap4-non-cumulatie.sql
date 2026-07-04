BEGIN;
-- T-045: cascade_stap4_doelgroepverminderingen met non-cumulatie via cumulatie_groep.
--        Voorwaarden_json extension: optionele "cumulatie_groep" key groepeert
--        elkaar-uitsluitende doelgroepen. Per groep wint de hoogste bijdrage.
--
-- Principe V: test-first commit.
-- Signature ongewijzigd; alleen internal CTE gewijzigd.
--
-- Test-strategie: hergebruik seed contract '9c42a18f-...' uit Demo BVBA
-- (Vlaanderen, PC 200, geboren 1976). Baseline stap4 is 0 (contract matcht
-- geen seed doelgroepen). Insert 3-4 test-scoped param_doelgroepvermindering
-- rijen en verifieer de gecalculeerde output. Alle inserts in BEGIN..ROLLBACK.

create extension if not exists pgtap;

select plan(5);


------------------------------------------------------------
-- T1: Function existence (signature onaangeraakt)
------------------------------------------------------------

select has_function(
    'public', 'cascade_stap4_doelgroepverminderingen',
    array['uuid', 'numeric', 'numeric', 'date'],
    'T1: cascade_stap4_doelgroepverminderingen(uuid, numeric, numeric, date) function exists'
);


------------------------------------------------------------
-- T2: Baseline check — seed contract heeft 0 doelgroep-bijdrage.
------------------------------------------------------------

select is(
    public.cascade_stap4_doelgroepverminderingen(
        (select c.contract_id from public.dim_contract c join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id where le.owning_account_id = 'a1111111-1111-1111-1111-111111111111'::uuid and c.pc_id = '200' order by c.geldig_van limit 1),
        3000.0000,
        1.0000,
        '2024-06-01'::date
    ),
    0.0000::numeric(18, 4),
    'T2 baseline: seed contract Demo BVBA #1 matcht geen seed doelgroepverminderingen -> 0.00'
);


------------------------------------------------------------
-- Setup: 3 test doelgroep-rijen — bucket A (100 en 250), solo (75).
--   Geen voorwaarden filters -> matchen elk contract in vlaanderen.
------------------------------------------------------------

insert into public.param_doelgroepvermindering (param_doelgroep_id, gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, voorwaarden_json, bron_url, bron_document) values
    ('45450000-0000-0000-0000-000000000501'::uuid, 'vlaanderen', 't045_bucket_A_lower',  '2020-01-01', '2030-01-01', 100.0000, 1.00000000, '{"cumulatie_groep":"test_vlaams_bucket"}'::jsonb, 'test://t045', 'T045 test — bucket A laag'),
    ('45450000-0000-0000-0000-000000000502'::uuid, 'vlaanderen', 't045_bucket_A_higher', '2020-01-01', '2030-01-01', 250.0000, 1.00000000, '{"cumulatie_groep":"test_vlaams_bucket"}'::jsonb, 'test://t045', 'T045 test — bucket A hoog (wint)'),
    ('45450000-0000-0000-0000-000000000503'::uuid, 'vlaanderen', 't045_solo',            '2020-01-01', '2030-01-01',  75.0000, 1.00000000, '{}'::jsonb, 'test://t045', 'T045 test — solo (geen groep, altijd tellen)');


------------------------------------------------------------
-- T3: Non-cumulatie werkt — bucket A wint met 250, solo telt volledig.
--     Verwacht: 250 (bucket A max) + 75 (solo) = 325.00.
------------------------------------------------------------

select is(
    public.cascade_stap4_doelgroepverminderingen(
        (select c.contract_id from public.dim_contract c join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id where le.owning_account_id = 'a1111111-1111-1111-1111-111111111111'::uuid and c.pc_id = '200' order by c.geldig_van limit 1),
        3000.0000,
        1.0000,
        '2024-06-01'::date
    ),
    325.0000::numeric(18, 4),
    'T3 non-cumulatie: bucket A (100+250) telt alleen 250 + solo 75 = 325.00 (per-bucket max ipv sum)'
);


------------------------------------------------------------
-- T4: Aparte buckets sommen apart — voeg 4e row in bucket B (40 euro).
--     Verwacht: 250 (bucket A max) + 75 (solo) + 40 (bucket B enige) = 365.00.
------------------------------------------------------------

insert into public.param_doelgroepvermindering (param_doelgroep_id, gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, voorwaarden_json, bron_url, bron_document) values
    ('45450000-0000-0000-0000-000000000504'::uuid, 'vlaanderen', 't045_bucket_B_only', '2020-01-01', '2030-01-01', 40.0000, 1.00000000, '{"cumulatie_groep":"test_ander_bucket"}'::jsonb, 'test://t045', 'T045 test — bucket B (aparte groep)');

select is(
    public.cascade_stap4_doelgroepverminderingen(
        (select c.contract_id from public.dim_contract c join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id where le.owning_account_id = 'a1111111-1111-1111-1111-111111111111'::uuid and c.pc_id = '200' order by c.geldig_van limit 1),
        3000.0000,
        1.0000,
        '2024-06-01'::date
    ),
    365.0000::numeric(18, 4),
    'T4 aparte buckets sommen: 250 (bucket A max) + 75 (solo) + 40 (bucket B enige) = 365.00'
);


------------------------------------------------------------
-- T5: mu-scaling nog steeds werkt — halveer mu -> totaal halveert.
--     Verwacht: 365 * 0.5 = 182.50.
------------------------------------------------------------

select is(
    public.cascade_stap4_doelgroepverminderingen(
        (select c.contract_id from public.dim_contract c join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id where le.owning_account_id = 'a1111111-1111-1111-1111-111111111111'::uuid and c.pc_id = '200' order by c.geldig_van limit 1),
        3000.0000,
        0.5000,
        '2024-06-01'::date
    ),
    182.5000::numeric(18, 4),
    'T5 mu-scaling: mu=0.5 halveert totaal (365/2=182.50) - bewijst Principe IV blijft werken'
);


select * from finish();
ROLLBACK;
