BEGIN;
create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(9);

select tests.create_supabase_user('test_reader');
select tests.authenticate_as('test_reader');


------------------------------------------------------------
-- Seed count (1 assertion)
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_looncomponent),
    12,
    'seed created 12 canonical loonvormen'
);


------------------------------------------------------------
-- KRITIEK: VAA-valkuil (2 assertions) — bedrijfswagen_vaa vs bedrijfswagen_tco
-- MOETEN opposite is_werkgeverskost hebben
------------------------------------------------------------

select is(
    (select is_werkgeverskost from public.dim_looncomponent where component_id = 'bedrijfswagen_vaa'),
    false,
    'VAA-valkuil deel 1: bedrijfswagen_vaa is NIET werkgeverskost (fiscale waardering voor werknemer)'
);

select is(
    (select is_werkgeverskost from public.dim_looncomponent where component_id = 'bedrijfswagen_tco'),
    true,
    'VAA-valkuil deel 2: bedrijfswagen_tco IS werkgeverskost (real cost)'
);


------------------------------------------------------------
-- Principe II negative test: 3 componenten same familie 'bedrijfswagen'
-- MOETEN 2 verschillende is_werkgeverskost waarden hebben (false + true).
-- Bewijst dat naam alleen niet gedrag drijft — cascade moet tags lezen.
------------------------------------------------------------

select is(
    (select count(distinct is_werkgeverskost)::int from public.dim_looncomponent where familie = 'bedrijfswagen'),
    2,
    'Principe II: familie=bedrijfswagen heeft 2 verschillende is_werkgeverskost waarden (behavior-as-data, niet name-as-behavior)'
);


------------------------------------------------------------
-- Baseline: basisloon heeft alle 4 gedragstags true (1 assertion)
------------------------------------------------------------

select is(
    (select (rsz_plichtig and is_werkgeverskost and telt_voor_vakantiegeld and telt_voor_mu)
       from public.dim_looncomponent where component_id = 'basisloon'),
    true,
    'basisloon: alle 4 gedragstags true (baseline behavior)'
);


------------------------------------------------------------
-- Extralegaal patroon (1 assertion): groepsverzekering rsz_plichtig=false
------------------------------------------------------------

select is(
    (select rsz_plichtig from public.dim_looncomponent where component_id = 'groepsverzekering'),
    false,
    'groepsverzekering rsz_plichtig=false (extralegaal patroon)'
);


------------------------------------------------------------
-- VIN forfaitair regime: gsm_prive verwijst naar vin_forfaitair (1 assertion)
------------------------------------------------------------

select is(
    (select sz_behandeling_id from public.dim_looncomponent where component_id = 'gsm_prive'),
    'vin_forfaitair',
    'gsm_prive sz_behandeling_id = vin_forfaitair (VIN forfaitair regime voor telecom-privegebruik)'
);


------------------------------------------------------------
-- CO2 verwijst naar VIN bijzondere formule (1 assertion, PDF fidelity F2)
------------------------------------------------------------

select is(
    (select sz_behandeling_id from public.dim_looncomponent where component_id = 'co2_solidariteitsbijdrage'),
    'vin_bijzondere_formule',
    'co2_solidariteitsbijdrage sz_behandeling_id = vin_bijzondere_formule (PDF Laag 2 aparte bijdrage)'
);


------------------------------------------------------------
-- All seed rows use only valid sz_behandeling_id from T-010 (1 assertion —
-- verifies FK integrity is holding after seed)
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_looncomponent lc
       where not exists (select 1 from public.dim_sz_behandeling sz where sz.sz_behandeling_id = lc.sz_behandeling_id)),
    0,
    'all 12 seed rows reference valid sz_behandeling_id in dim_sz_behandeling (FK integrity)'
);


select * from finish();
ROLLBACK;
