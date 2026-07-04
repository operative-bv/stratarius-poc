BEGIN;
-- T-027: cascade_stap4_doelgroepverminderingen JSONB rule engine.
-- Depends: HOTFIX A (dim_legale_entiteit.gewest), HOTFIX B (dim_persoon_arbeidsverleden),
--          T-014 seed (6 doelgroepen VDAB/Forem/Actiris).
--
-- Principe V: TDD verified via manual docker psql smoke (pgTAP lokaal geblokt door ISS-030).

create extension "basejump-supabase_test_helpers" version '0.0.6';
select plan(11);

-- Function + schema existence
select has_function('public', 'cascade_stap4_doelgroepverminderingen', array['uuid', 'numeric', 'numeric', 'date'], 'T1');
select has_column('public', 'dim_legale_entiteit', 'gewest', 'T2 HOTFIX A');
select has_table('public', 'dim_persoon_arbeidsverleden', 'T3 HOTFIX B');

-- Setup: 3 legale_entiteiten (VL/WA/BR) + 6 personen met specifieke profielen + 6 contracten
select tests.create_supabase_user('t');
select tests.authenticate_as('t');

insert into basejump.accounts (id, name, slug, personal_account) values
    ('a1111111-1111-1111-1111-111111111111', 'T', 'ts', false);

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id, gewest) values
    ('aaaaaaaa-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 1, 'VL', 'BE', 'vlaanderen'),
    ('aaaaaaaa-0000-0000-0000-000000000002', 'a1111111-1111-1111-1111-111111111111', 1, 'WA', 'BE', 'wallonie'),
    ('aaaaaaaa-0000-0000-0000-000000000003', 'a1111111-1111-1111-1111-111111111111', 1, 'BR', 'BE', 'brussel');

insert into public.dim_functie (functie_id, owning_account_id, functienaam) values ('f1000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'F');

insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum, opleidingsniveau) values
    ('11111111-1111-1111-1111-000000000001', 'a1111111-1111-1111-1111-111111111111', 'v', '1962-01-01', 'hooggeschoold'),
    ('22222222-2222-2222-2222-000000000002', 'a1111111-1111-1111-1111-111111111111', 'm', '2002-01-01', 'laaggeschoold'),
    ('33333333-3333-3333-3333-000000000003', 'a1111111-1111-1111-1111-111111111111', 'x', '2001-01-01', 'laag_of_middel_geschoold'),
    ('44444444-4444-4444-4444-000000000004', 'a1111111-1111-1111-1111-111111111111', 'm', '1994-01-01', 'middel_geschoold'),
    ('55555555-5555-5555-5555-000000000005', 'a1111111-1111-1111-1111-111111111111', 'v', '1968-01-01', 'hooggeschoold'),
    ('66666666-6666-6666-6666-000000000006', 'a1111111-1111-1111-1111-111111111111', 'm', '1990-01-01', 'hooggeschoold');

insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van) values
    ('c1000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2023-01-01'),
    ('c2000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2023-06-01'),
    ('c3000000-0000-0000-0000-000000000003', '33333333-3333-3333-3333-000000000003', 'aaaaaaaa-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2022-05-01'),
    ('c4000000-0000-0000-0000-000000000004', '44444444-4444-4444-4444-000000000004', 'aaaaaaaa-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2022-05-01'),
    ('c5000000-0000-0000-0000-000000000005', '55555555-5555-5555-5555-000000000005', 'aaaaaaaa-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2023-06-01'),
    ('c6000000-0000-0000-0000-000000000006', '66666666-6666-6666-6666-000000000006', 'aaaaaaaa-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2020-01-01');

insert into public.dim_persoon_arbeidsverleden (persoon_id, owning_account_id, werkloosheidsperiode_van, werkloosheidsperiode_tot, bron) values
    ('44444444-4444-4444-4444-000000000004', 'a1111111-1111-1111-1111-111111111111', '2021-01-01', '2022-04-01', 'RVA'),
    ('55555555-5555-5555-5555-000000000005', 'a1111111-1111-1111-1111-111111111111', '2022-11-01', '2023-06-01', 'Actiris');

-- Doelgroep matches
select is(public.cascade_stap4_doelgroepverminderingen('c1000000-0000-0000-0000-000000000001'::uuid, 4000.0000, 1.0000, '2024-01-01'::date), 600.0000::numeric(18,4), 'T4 VL oudere_werknemer 62j → 600');
select is(public.cascade_stap4_doelgroepverminderingen('c2000000-0000-0000-0000-000000000002'::uuid, 2500.0000, 1.0000, '2024-01-01'::date), 1000.0000::numeric(18,4), 'T5 VL jongere_zonder_diploma 22j laaggeschoold → 1000');
select is(public.cascade_stap4_doelgroepverminderingen('c3000000-0000-0000-0000-000000000003'::uuid, 3000.0000, 1.0000, '2024-01-01'::date), 500.0000::numeric(18,4), 'T6 WA impulsion_jongere 23j → 500');
select is(public.cascade_stap4_doelgroepverminderingen('c4000000-0000-0000-0000-000000000004'::uuid, 3000.0000, 1.0000, '2024-01-01'::date), 500.0000::numeric(18,4), 'T7 WA impulsion_langdurig_werkloos 15m → 500');
select is(public.cascade_stap4_doelgroepverminderingen('c5000000-0000-0000-0000-000000000005'::uuid, 4000.0000, 1.0000, '2024-01-01'::date), 1000.0000::numeric(18,4), 'T8 BR activa_50plus 56j 7m werkloos → 1000');

-- Negatief + Principe IV + temporele
select is(public.cascade_stap4_doelgroepverminderingen('c6000000-0000-0000-0000-000000000006'::uuid, 4000.0000, 1.0000, '2024-01-01'::date), 0.0000::numeric(18,4), 'T9 geen match → 0');
select is(public.cascade_stap4_doelgroepverminderingen('c1000000-0000-0000-0000-000000000001'::uuid, 4000.0000, 0.5000, '2024-01-01'::date), 300.0000::numeric(18,4), 'T13 KEY Principe IV μ=0.5 → 300');
select is(public.cascade_stap4_doelgroepverminderingen('c1000000-0000-0000-0000-000000000001'::uuid, 4000.0000, 1.0000, '2023-01-01'::date), 0.0000::numeric(18,4), 'T15 temporele miss → 0');

select * from finish();
ROLLBACK;
