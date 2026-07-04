BEGIN;
-- T-024: mu_van_prestatie(contract_id, periode) pure functie.
-- Depends on: dim_prestatiecode (T-013), param_arbeidsduur (T-017+T-019 imports),
--             dim_contract (T-006), fact_prestatie (T-022).
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration. Bij eerste run zonder migration MOET dit falen (Red).
--
-- Principe IV KRITIEK: μ berekening gebruikt GEEN dim_contract.fte_breuk.
--   Test T4 bewijst dit expliciet — contract C heeft fte_breuk=0.5 maar μ=0.6072.
--
-- Formule: μ = Q / S waar
--   Q = SUM(fact_prestatie.uren) WHERE dim_prestatiecode.telt_voor_mu = true
--   S = param_arbeidsduur.gemiddelde_wekelijkse_uren × (52/12) — ref-uren per maand

create extension if not exists pgtap;

select plan(9);

-- Setup: 1 tenant met 3 contracten (A voltijds PC 200, B voltijds PC 124, C deeltijds PC 200)
select tests.create_supabase_user('tenant_a_owner');
select tests.authenticate_as('tenant_a_owner');

insert into basejump.accounts (id, name, slug, personal_account) values
    ('a1111111-1111-1111-1111-111111111111', 'Tenant', 'tenant', false);

insert into public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id) values
    ('aaaaaaaa-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 1, 'Test BVBA', 'BE');

insert into public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum) values
    ('a2222222-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'v', '1985-01-01'),
    ('b2222222-2222-2222-2222-222222222222', 'a1111111-1111-1111-1111-111111111111', 'm', '1990-01-01'),
    ('c2222222-3333-3333-3333-333333333333', 'a1111111-1111-1111-1111-111111111111', 'v', '1995-01-01');

insert into public.dim_functie (functie_id, owning_account_id, functienaam) values
    ('f1000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'Test Functie');

-- Contract A: PC 200 (38u/week → S=164.6667), voltijds
insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van) values
    ('aa000000-0000-0000-0000-000000000001', 'a2222222-1111-1111-1111-111111111111', 'aaaaaaaa-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 1.0000, '2024-01-01');
-- Contract B: PC 124 (40u/week → S=173.3333), voltijds
insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van) values
    ('bb000000-0000-0000-0000-000000000002', 'b2222222-2222-2222-2222-222222222222', 'aaaaaaaa-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000001', '124', 'arbeider', 1.0000, '2024-01-01');
-- Contract C: PC 200 (38u/week → S=164.6667), DEELTIJDS fte_breuk=0.5
insert into public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van) values
    ('cc000000-0000-0000-0000-000000000003', 'c2222222-3333-3333-3333-333333333333', 'aaaaaaaa-1111-1111-1111-111111111111', 'f1000000-0000-0000-0000-000000000001', '200', 'bediende', 0.5000, '2024-01-01');


------------------------------------------------------------
-- Function existence (1 assertion)
------------------------------------------------------------

select has_function(
    'public', 'mu_van_prestatie',
    array['uuid', 'date'],
    'public.mu_van_prestatie(uuid, date) function exists'
);


------------------------------------------------------------
-- T1: Voltijds baseline μ = 1.0000 (Contract A, 164.6667 uren normaal_gewerkt)
-- Q = 164.6667, S = 38 × 52/12 = 164.6667, μ = 1.0000 exact
------------------------------------------------------------

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('aa000000-0000-0000-0000-000000000001', '2024-01-01', 'normaal_gewerkt', 164.6667, 21.0000);

select is(
    public.mu_van_prestatie('aa000000-0000-0000-0000-000000000001'::uuid, '2024-01-01'::date),
    1.0000::numeric(6,4),
    'T1 voltijds baseline: PC 200 164.6667 uren normaal_gewerkt → mu = 1.0000 (Q=S exact)'
);


------------------------------------------------------------
-- T2: Tijdelijke urenvermindering — KEY test voor telt_voor_mu filter
-- Contract A periode 2024-02: 60u normaal_gewerkt + 20u tijdelijke_urenvermindering
-- Q = 60 (NIET 80 want telt_voor_mu=false op tijdelijke_urenvermindering)
-- μ = 60 / 164.6667 = 0.3644
------------------------------------------------------------

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('aa000000-0000-0000-0000-000000000001', '2024-02-01', 'normaal_gewerkt', 60.0000, 8.0000),
    ('aa000000-0000-0000-0000-000000000001', '2024-02-01', 'tijdelijke_urenvermindering', 20.0000, 3.0000);

select is(
    public.mu_van_prestatie('aa000000-0000-0000-0000-000000000001'::uuid, '2024-02-01'::date),
    0.3644::numeric(6,4),
    'T2 tijdelijke urenvermindering: 60u normaal_gewerkt + 20u tijdelijke_urenvermindering → mu = 0.3644 (60/164.6667; bewijst telt_voor_mu filter werkt)'
);


------------------------------------------------------------
-- T3: PC 124 outlier — μ = 1.0000
-- Contract B: 173.3333 uren normaal_gewerkt. S = 40 × 52/12 = 173.3333. μ = 1.0000
------------------------------------------------------------

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('bb000000-0000-0000-0000-000000000002', '2024-01-01', 'normaal_gewerkt', 173.3333, 22.0000);

select is(
    public.mu_van_prestatie('bb000000-0000-0000-0000-000000000002'::uuid, '2024-01-01'::date),
    1.0000::numeric(6,4),
    'T3 PC 124 outlier: 173.3333u normaal_gewerkt / S=173.3333 (40u/week bouw) → mu = 1.0000'
);


------------------------------------------------------------
-- T4: fte_breuk ≠ μ — KEY test voor Principe IV separation
-- Contract C fte_breuk=0.5 MAAR 100u normaal_gewerkt werkelijk
-- Q = 100.0000, S = 164.6667 (uit PC 200 param_arbeidsduur, ONAFHANKELIJK van fte_breuk!)
-- μ = 100 / 164.6667 = 0.6072 (NIET 0.5!)
------------------------------------------------------------

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('cc000000-0000-0000-0000-000000000003', '2024-01-01', 'normaal_gewerkt', 100.0000, 13.0000);

select is(
    public.mu_van_prestatie('cc000000-0000-0000-0000-000000000003'::uuid, '2024-01-01'::date),
    0.6073::numeric(6,4),
    'T4 Principe IV: contract fte_breuk=0.5 MAAR 100u werkelijk → mu = 0.6073 (100/164.6667; NIET 0.5 — function gebruikt geen fte_breuk)'
);


------------------------------------------------------------
-- T5: Overuren μ > 1
-- Contract A periode 2024-03: 200u normaal_gewerkt. Q=200, S=164.6667. μ=1.2145
------------------------------------------------------------

insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen) values
    ('aa000000-0000-0000-0000-000000000001', '2024-03-01', 'normaal_gewerkt', 200.0000, 25.0000);

select is(
    public.mu_van_prestatie('aa000000-0000-0000-0000-000000000001'::uuid, '2024-03-01'::date),
    1.2146::numeric(6,4),
    'T5 overuren: 200u normaal_gewerkt / 164.6667 → mu = 1.2146 > 1.0 (Principe IV staat overuren via mu > 1 toe)'
);


------------------------------------------------------------
-- T6: Missing fact_prestatie → μ = 0
-- Contract A periode 2024-04 zonder fact_prestatie. Q=0 (coalesce), S=164.6667, μ=0.0000
------------------------------------------------------------

select is(
    public.mu_van_prestatie('aa000000-0000-0000-0000-000000000001'::uuid, '2024-04-01'::date),
    0.0000::numeric(6,4),
    'T6 missing fact_prestatie voor periode → mu = 0.0000 (coalesce sum, S bestaat nog steeds)'
);


------------------------------------------------------------
-- T7: Missing param_arbeidsduur → NULL
-- Contract met pc_id waar geen param_arbeidsduur voor die periode:
-- Contract A periode 2023-01-01 (voor param_arbeidsduur.geldig_van 2024-01-01)
------------------------------------------------------------

select is(
    public.mu_van_prestatie('aa000000-0000-0000-0000-000000000001'::uuid, '2023-01-01'::date),
    null::numeric(6,4),
    'T7 periode voor param_arbeidsduur.geldig_van → NULL (cross-join met lege S → geen output; caller detecteert)'
);


------------------------------------------------------------
-- T8: Determinisme
------------------------------------------------------------

select is(
    public.mu_van_prestatie('aa000000-0000-0000-0000-000000000001'::uuid, '2024-01-01'::date),
    public.mu_van_prestatie('aa000000-0000-0000-0000-000000000001'::uuid, '2024-01-01'::date),
    'T8 determinisme: 2 opeenvolgende calls met identieke inputs → identieke output (STABLE PARALLEL SAFE)'
);


select * from finish();
ROLLBACK;
