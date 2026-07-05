BEGIN;
-- T-026: cascade_stap1_rsz_grondslag(contract_id, periode, scenario_id) pure functie.
-- Depends on: dim_looncomponent + is_basisloon HOTFIX (in migration),
--             fact_looncomponent (T-022), fact_prestatie (T-022),
--             dim_prestatiecode (T-013), param_arbeidsduur (T-017/T-019),
--             uurloon_van_maandloon (T-023).
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration. Bij eerste run zonder migration MOET has_function + has_column falen (Red).
--
-- Constitution Principe II: filters op gedragstags (rsz_plichtig, is_basisloon,
--   toeslag_pct IS NOT NULL) — NOOIT switching op component_id/prestatiecode identity.
--
-- Scope-reductie 2026-07-03 (plan-review round 1 folds):
--   T-026 origineel was stap 1-3 in één ticket. Reviewer vond 4 critical blockers
--   waaronder unresolved "wat is basisloon" design. Rescoped naar stap 1 only.
--   Stap 2 → T-041, stap 3 (met S0/S1 hotfix) → T-042.
--
-- Formule:
--   RSZ_grondslag = som_rsz_plichtige + overloon
--
--   som_rsz_plichtige = COALESCE(SUM(fact_looncomponent.bedrag), 0)
--                       WHERE dim_looncomponent.rsz_plichtig = true
--                         AND (contract_id, periode, scenario_id) match
--
--   maandloon = COALESCE(SUM(fact_looncomponent.bedrag), 0)
--               WHERE dim_looncomponent.is_basisloon = true
--                 AND (contract_id, periode, scenario_id) match
--
--   uurloon = uurloon_van_maandloon(maandloon, contract.pc_id, periode)
--
--   overloon = COALESCE(SUM(fact_prestatie.uren × uurloon × dim_prestatiecode.toeslag_pct), 0)
--              WHERE dim_prestatiecode.toeslag_pct IS NOT NULL
--                AND (contract_id, periode) match

create extension if not exists pgtap;

select plan(12);

-- ============================================================
-- Setup: 1 tenant + 2 contracten
-- ============================================================

-- Setup als postgres (ISS-085 pattern; unit test → geen authenticate_as)
select tests.create_supabase_user('tenant_a_owner');

insert into basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) values
    ('43430100-1111-1111-1111-111111111111', 'Tenant', 'tenant-43', false, tests.get_supabase_uid('tenant_a_owner'));
insert into basejump.account_user (user_id, account_id, account_role) values
    (tests.get_supabase_uid('tenant_a_owner'), '43430100-1111-1111-1111-111111111111', 'owner');

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('43430200-1111-1111-1111-111111111111', '43430100-1111-1111-1111-111111111111', 1, 'Test BVBA', 'BE');

insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum) values
    ('a2222222-1111-1111-1111-111111111111', '43430100-1111-1111-1111-111111111111', 'v', '1985-01-01'),
    ('b2222222-2222-2222-2222-222222222222', '43430100-1111-1111-1111-111111111111', 'm', '1990-01-01');

insert into public.dim_functie (functie_id, owning_account_id, functienaam) values
    ('43430400-0000-0000-0000-000000000001', '43430100-1111-1111-1111-111111111111', 'Test Functie');

-- Contract A: PC 200 (38u/week), bediende, voltijds
insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van) values
    ('aa000000-0000-0000-0000-000000000001', 'a2222222-1111-1111-1111-111111111111',
     '43430200-1111-1111-1111-111111111111', '43430400-0000-0000-0000-000000000001',
     '200', 'bediende', 1.0000, '2024-01-01');

-- Contract B: PC 124 (40u/week), arbeider, voltijds (voor NULL-contract test T11)
insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van) values
    ('bb000000-0000-0000-0000-000000000002', 'b2222222-2222-2222-2222-222222222222',
     '43430200-1111-1111-1111-111111111111', '43430400-0000-0000-0000-000000000001',
     '124', 'arbeider', 1.0000, '2024-01-01');

-- 2 scenarios: baseline + what-if (voor scenario-isolatie test T6)
insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind) values
    ('43430500-1111-1111-1111-111111111111', '43430200-1111-1111-1111-111111111111', 'baseline', 'baseline'),
    ('43430500-2222-2222-2222-222222222222', '43430200-1111-1111-1111-111111111111', 'what-if', 'what_if');


------------------------------------------------------------
-- T1, T2: Function + HOTFIX existence
------------------------------------------------------------

select has_function(
    'public', 'cascade_stap1_rsz_grondslag',
    array['uuid', 'date', 'uuid'],
    'T1: public.cascade_stap1_rsz_grondslag(uuid, date, uuid) function exists'
);

select has_column(
    'public', 'dim_looncomponent', 'is_basisloon',
    'T2: HOTFIX applied — dim_looncomponent.is_basisloon column exists'
);


------------------------------------------------------------
-- T3: Sanity — alleen basisloon → grondslag = 4000
------------------------------------------------------------

insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values
    ('aa000000-0000-0000-0000-000000000001', '2024-01-01', 'basisloon',
     '43430500-1111-1111-1111-111111111111', 4000.0000);

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-01-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    4000.0000::numeric(18, 4),
    'T3 sanity: basisloon 4000 → grondslag = 4000.0000 (som rsz_plichtige, overloon=0)'
);


------------------------------------------------------------
-- T4: basisloon + premie_maandelijks (beide rsz_plichtig) → 4100
------------------------------------------------------------

insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values
    ('aa000000-0000-0000-0000-000000000001', '2024-02-01', 'basisloon',
     '43430500-1111-1111-1111-111111111111', 4000.0000),
    ('aa000000-0000-0000-0000-000000000001', '2024-02-01', 'premie_maandelijks',
     '43430500-1111-1111-1111-111111111111', 100.0000);

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-02-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    4100.0000::numeric(18, 4),
    'T4 multi-component rsz_plichtige: basisloon 4000 + premie 100 → 4100.0000'
);


------------------------------------------------------------
-- T5: VAA filter — bedrijfswagen_vaa NIET rsz_plichtig → wordt gefilterd
------------------------------------------------------------

insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values
    ('aa000000-0000-0000-0000-000000000001', '2024-03-01', 'basisloon',
     '43430500-1111-1111-1111-111111111111', 4000.0000),
    ('aa000000-0000-0000-0000-000000000001', '2024-03-01', 'bedrijfswagen_vaa',
     '43430500-1111-1111-1111-111111111111', 200.0000);

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-03-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    4000.0000::numeric(18, 4),
    'T5 VAA filter: basisloon 4000 + VAA 200 → 4000.0000 (VAA rsz_plichtig=false, gefilterd — Principe II bewijs)'
);


------------------------------------------------------------
-- T6: Scenario-isolatie — 2 scenarios met verschillende basislonen
------------------------------------------------------------

insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values
    ('aa000000-0000-0000-0000-000000000001', '2024-04-01', 'basisloon',
     '43430500-1111-1111-1111-111111111111', 3000.0000),
    ('aa000000-0000-0000-0000-000000000001', '2024-04-01', 'basisloon',
     '43430500-2222-2222-2222-222222222222', 5000.0000);

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-04-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    3000.0000::numeric(18, 4),
    'T6 scenario baseline: basisloon 3000 in baseline, 5000 in what-if → returnt 3000 (baseline scenario_id)'
);


------------------------------------------------------------
-- T7: Missing fact_looncomponent → 0.0000 (COALESCE, NIET NULL)
------------------------------------------------------------

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-05-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    0.0000::numeric(18, 4),
    'T7 missing fact voor periode → 0.0000 (COALESCE explicit, geen NULL propagation naar downstream)'
);


------------------------------------------------------------
-- T8: Overloon — basisloon + 10u op prestatiecode overuren_50 (toeslag_pct=0.50)
--     uurloon = (4000 × 3) / (13 × 38) = 24.2915
--     overloon = 10 × 24.2915 × 0.50 = 121.4575
--     totaal = 4000 + 121.4575 = 4121.4575
------------------------------------------------------------

insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values
    ('aa000000-0000-0000-0000-000000000001', '2024-06-01', 'basisloon',
     '43430500-1111-1111-1111-111111111111', 4000.0000);

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('aa000000-0000-0000-0000-000000000001', '2024-06-01', 'overuren_50', 10.0000, 2.0000);

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-06-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    4121.4575::numeric(18, 4),
    'T8 overloon: basisloon 4000 + 10u overuren_50 × uurloon 24.2915 × 0.50 = 4121.4575'
);


------------------------------------------------------------
-- T9: Overloon-filter — normaal_gewerkt uren (toeslag_pct=NULL) NIET meegeteld
------------------------------------------------------------

insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values
    ('aa000000-0000-0000-0000-000000000001', '2024-07-01', 'basisloon',
     '43430500-1111-1111-1111-111111111111', 4000.0000);

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('aa000000-0000-0000-0000-000000000001', '2024-07-01', 'normaal_gewerkt', 160.0000, 21.0000);

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-07-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    4000.0000::numeric(18, 4),
    'T9 overloon filter: normaal_gewerkt (toeslag_pct=NULL) NIET meegeteld → grondslag = 4000 (Principe II filter)'
);


------------------------------------------------------------
-- T10: Alleen overuren zonder basisloon → maandloon=0 → uurloon=0 → overloon=0 → grondslag=0
--      Documented behavior: geen basisloon = geen overloon-berekening.
------------------------------------------------------------

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('aa000000-0000-0000-0000-000000000001', '2024-08-01', 'overuren_50', 10.0000, 2.0000);

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-08-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    0.0000::numeric(18, 4),
    'T10 overuren zonder basisloon: maandloon=0 → uurloon=0 → overloon=0 → grondslag=0.0000 (documented)'
);


------------------------------------------------------------
-- T11: NULL contract — periode voor param_arbeidsduur.geldig_van
--      Als er overuren zijn: uurloon = NULL → overloon = NULL → grondslag = NULL.
--      (Als GEEN overuren: grondslag = alleen som componenten; hier hebben we wel overuren dus NULL.)
------------------------------------------------------------

insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag) values
    ('aa000000-0000-0000-0000-000000000001', '2023-01-01', 'basisloon',
     '43430500-1111-1111-1111-111111111111', 4000.0000);

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('aa000000-0000-0000-0000-000000000001', '2023-01-01', 'overuren_50', 10.0000, 2.0000);

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2023-01-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    null::numeric(18, 4),
    'T11 NULL contract: periode 2023-01 (voor param_arbeidsduur.geldig_van 2024-01) + overuren → uurloon NULL → grondslag NULL. Caller detecteert (fold NULL-contract expliciet gedocumenteerd)'
);


------------------------------------------------------------
-- T12: Determinisme
------------------------------------------------------------

select is(
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-06-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    public.cascade_stap1_rsz_grondslag(
        'aa000000-0000-0000-0000-000000000001'::uuid,
        '2024-06-01'::date,
        '43430500-1111-1111-1111-111111111111'::uuid
    ),
    'T12 determinisme: 2 opeenvolgende calls met identieke inputs → identieke outputs (STABLE PARALLEL SAFE)'
);


select * from finish();
ROLLBACK;
