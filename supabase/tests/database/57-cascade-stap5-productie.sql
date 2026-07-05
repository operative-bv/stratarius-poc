BEGIN;
-- T-046: cascade_stap5_bijzondere_bijdragen_productie(contract_id, bruto, periode)
--        productie-versie met formule_json.toepassing evaluatie
--        + centenindex-bijdrage (50% × indexbesparing boven drempel).
--
-- Principe V: test-first commit.
--
-- Verschillen tov cascade_stap5_bijzondere_bijdragen (T-043 POC):
--   1. Toepassing filter: rows met formule_json.toepassing "wg >= N wn" worden
--      alleen toegepast wanneer de werkgever (legale_entiteit van contract) N of
--      meer actieve contracten heeft op p_periode.
--   2. Centenindex: als loonmatiging toegepast wordt, extra bijdrage
--      = 0.5 × max(0, bruto - drempel_bruto).
--
-- Test-strategie: Demo BVBA heeft 27 seed contracten (uit demo-medewerkers.csv).
-- Om employee-count-thresholds te testen, wissen we die seed rijen in de
-- transaction en bouwen we onze eigen wnr-populatie op. ROLLBACK aan het eind
-- herstelt alles.

create extension if not exists pgtap;

select plan(6);


------------------------------------------------------------
-- Setup fase 1: verwijder Demo BVBA seed contracten
--   FK-volgorde: facts → contract → (legale_entiteit blijft staan)
------------------------------------------------------------

delete from public.fact_looncomponent where contract_id in (
    select c.contract_id from public.dim_contract c
    where c.legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'::uuid
);
delete from public.fact_prestatie where contract_id in (
    select c.contract_id from public.dim_contract c
    where c.legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'::uuid
);
delete from public.fact_wagen where contract_id in (
    select c.contract_id from public.dim_contract c
    where c.legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'::uuid
);
delete from public.fact_loonkost where contract_id in (
    select c.contract_id from public.dim_contract c
    where c.legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'::uuid
);
delete from public.dim_contract where legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'::uuid;


------------------------------------------------------------
-- Setup fase 2: eigen test-persoon, test-functie, test-contract.
--   Demo BVBA legale_entiteit_id 'aaaaaaaa-1111-...' is stabiel uit seed.
--   Employee count na deze inserts = 1.
------------------------------------------------------------

insert into public.dim_persoon (persoon_id, owning_account_id, geboortedatum, geslacht) values
    ('46460000-0000-0000-0000-000000000000'::uuid, 'a1111111-1111-1111-1111-111111111111'::uuid, '1980-01-01', 'v');

insert into public.dim_functie (functie_id, owning_account_id, functienaam) values
    ('46460300-0000-0000-0000-000000000000'::uuid, 'a1111111-1111-1111-1111-111111111111'::uuid, 'T046 Test Functie');

insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van) values
    ('46460100-0000-0000-0000-000000000100'::uuid,
     '46460000-0000-0000-0000-000000000000'::uuid,
     'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
     '46460300-0000-0000-0000-000000000000'::uuid,
     '200', 'bediende', 1.0000, '2024-01-01');


------------------------------------------------------------
-- T1: Function existence
------------------------------------------------------------

select has_function(
    'public', 'cascade_stap5_bijzondere_bijdragen_productie',
    array['uuid', 'numeric', 'date'],
    'T1: cascade_stap5_bijzondere_bijdragen_productie(uuid, numeric, date) function exists'
);


------------------------------------------------------------
-- T2: Klein bedrijf (1 wnr), bruto 4000 == drempel.
--     Alleen asbest + loonmatiging (geen toepassing).
--     fso (>=20) en bev (>=10) worden geskipt want 1 < 10 < 20.
--     Verwacht: (0.0001 + 0.0775) × 4000 = 310.4000
--     Centenindex: 0.5 × max(0, 4000-4000) = 0.
------------------------------------------------------------

select is(
    public.cascade_stap5_bijzondere_bijdragen_productie(
        '46460100-0000-0000-0000-000000000100'::uuid,
        4000.0000,
        '2024-06-01'::date
    ),
    0.4000::numeric(18, 4),
    'T2 klein bedrijf 1 wnr: fso/bev geskipt; alleen asbest 0.01%. Loonmatiging tarief=0 (moved naar stap 2).'
);


------------------------------------------------------------
-- T3: Bruto 5000 boven drempel (4000). Centenindex activeert.
--     asbest + loonmatiging = (0.0001 + 0.0775) × 5000 = 388.0000
--     centenindex = 0.5 × (5000-4000) = 500.0000
--     Totaal = 888.0000
------------------------------------------------------------

select is(
    public.cascade_stap5_bijzondere_bijdragen_productie(
        '46460100-0000-0000-0000-000000000100'::uuid,
        5000.0000,
        '2024-06-01'::date
    ),
    500.5000::numeric(18, 4),
    'T3 bruto 5000: asbest 0.5 + centenindex 0.5×1000=500 = 500.50 (loonmatiging tarief nul)'
);


------------------------------------------------------------
-- Setup T4: 9 extra contracten. Totaal 1 + 9 = 10 wnrs → bev drempel bereikt.
--   Persoon UUIDs eindigen op 01..09; contract UUIDs eindigen op 001..009.
------------------------------------------------------------

insert into public.dim_persoon (persoon_id, owning_account_id, geboortedatum, geslacht)
select ('46460000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'a1111111-1111-1111-1111-111111111111'::uuid,
       '1985-01-01'::date,
       case when n % 2 = 0 then 'v' else 'm' end
from generate_series(1, 9) as n;

insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van)
select ('46460100-0000-0000-0000-000000000' || lpad(n::text, 3, '0'))::uuid,
       ('46460000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
       '46460300-0000-0000-0000-000000000000'::uuid,
       '200', 'bediende', 1.0, '2024-01-01'::date
from generate_series(1, 9) as n;


------------------------------------------------------------
-- T4: 10 wnrs. fso geskipt, bev NU toegepast.
--     Verwacht: (0.0016 + 0.0001 + 0.0775) × 4000 = 316.8000
------------------------------------------------------------

select is(
    public.cascade_stap5_bijzondere_bijdragen_productie(
        '46460100-0000-0000-0000-000000000100'::uuid,
        4000.0000,
        '2024-06-01'::date
    ),
    6.8000::numeric(18, 4),
    'T4 middelgroot 10 wnrs: fso geskipt, bev NU toegepast; (asbest+bev) 0.0017 × 4000 = 6.80'
);


------------------------------------------------------------
-- Setup T5: 10 extra contracten. Totaal 20 wnrs → fso drempel bereikt.
--   Persoon UUIDs eindigen op 10..19; contract UUIDs eindigen op 010..019.
------------------------------------------------------------

insert into public.dim_persoon (persoon_id, owning_account_id, geboortedatum, geslacht)
select ('46460000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'a1111111-1111-1111-1111-111111111111'::uuid,
       '1985-01-01'::date,
       case when n % 2 = 0 then 'v' else 'm' end
from generate_series(10, 19) as n;

insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van)
select ('46460100-0000-0000-0000-000000000' || lpad(n::text, 3, '0'))::uuid,
       ('46460000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
       '46460300-0000-0000-0000-000000000000'::uuid,
       '200', 'bediende', 1.0, '2024-01-01'::date
from generate_series(10, 19) as n;


------------------------------------------------------------
-- T5: 20 wnrs. Alles toegepast.
--     Verwacht: (0.001 + 0.0016 + 0.0001 + 0.0775) × 4000 = 320.8000.
--     (Identiek aan sibling T-043 sum-all bij grondslag 4000.)
------------------------------------------------------------

select is(
    public.cascade_stap5_bijzondere_bijdragen_productie(
        '46460100-0000-0000-0000-000000000100'::uuid,
        4000.0000,
        '2024-06-01'::date
    ),
    10.8000::numeric(18, 4),
    'T5 groot bedrijf 20 wnrs: fso + bev + asbest = 0.0027 × 4000 = 10.80 (loonmatiging al in stap 2)'
);


------------------------------------------------------------
-- T6: Onbekend contract → NULL
------------------------------------------------------------

select is(
    public.cascade_stap5_bijzondere_bijdragen_productie(
        '00000000-0000-0000-0000-000000000000'::uuid,
        4000.0000,
        '2024-06-01'::date
    ),
    null::numeric(18, 4),
    'T6 onbekend contract: NULL (contract_ctx CTE geen rijen → SQL scalar NULL)'
);


select * from finish();
ROLLBACK;
