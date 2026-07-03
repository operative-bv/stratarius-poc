BEGIN;
-- T-042: cascade_stap3_structurele_vermindering pure functie.
-- Formule: R = (F + α × GREATEST(0, S0-S) + δ × GREATEST(0, S-S1)) × μ
-- Principe IV KRITIEK: μ (niet fte_breuk) drijft R pro rata. Function accepteert
-- p_mu als parameter; leest GEEN dim_contract.fte_breuk.
--
-- Seed T-018 + T-042 HOTFIX:
--   Cat 1: F=0,    α=0.1400, δ=0
--   Cat 2: F=49,   α=0.2641, δ=0
--   Cat 3: F=375,  α=0.1714, δ=0.0686
--   S0=7207.20, S1=12435.31 (RSZ 2024 waardes)

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(12);


------------------------------------------------------------
-- T1: Function existence
------------------------------------------------------------

select has_function(
    'public', 'cascade_stap3_structurele_vermindering',
    array['numeric', 'numeric', 'smallint', 'date'],
    'T1: function exists'
);


------------------------------------------------------------
-- Cat 1: F=0, α=0.14, δ=0 — alleen laag-lonencomponent
------------------------------------------------------------

-- T2: S=6000 (< S0), μ=1.0 → 0 + 0.14 × (7207.20-6000) + 0 = 168.9080
select is(
    public.cascade_stap3_structurele_vermindering(6000.0000, 1.0000, 1::smallint, '2024-01-01'::date),
    168.9080::numeric(18, 4),
    'T2 cat 1 laag loon: S=6000 → 0 + 0.14 × 1207.20 = 168.9080'
);

-- T3: S=8000 (tussen S0 en S1), μ=1.0 → 0 + 0 + 0 = 0 (deadband)
select is(
    public.cascade_stap3_structurele_vermindering(8000.0000, 1.0000, 1::smallint, '2024-01-01'::date),
    0.0000::numeric(18, 4),
    'T3 cat 1 deadband: S=8000 tussen S0 en S1 → 0 (geen vermindering)'
);

-- T4: S=15000 (> S1), μ=1.0 → 0 + 0 + 0 × (15000-12435.31) = 0 (cat 1 δ=0)
select is(
    public.cascade_stap3_structurele_vermindering(15000.0000, 1.0000, 1::smallint, '2024-01-01'::date),
    0.0000::numeric(18, 4),
    'T4 cat 1 hoog loon δ=0: S=15000 → 0 (cat 1 heeft geen hoog-lonencomponent)'
);


------------------------------------------------------------
-- Cat 2: F=49, α=0.2641, δ=0
------------------------------------------------------------

-- T5: S=6000, μ=1.0 → 49 + 0.2641 × 1207.20 = 49 + 318.82152 = 367.8215
select is(
    public.cascade_stap3_structurele_vermindering(6000.0000, 1.0000, 2::smallint, '2024-01-01'::date),
    367.8215::numeric(18, 4),
    'T5 cat 2 laag loon: 49 + 0.2641 × 1207.20 = 367.8215'
);


------------------------------------------------------------
-- Cat 3: F=375, α=0.1714, δ=0.0686 — beide componenten
------------------------------------------------------------

-- T6: S=6000, μ=1.0 → 375 + 0.1714 × 1207.20 + 0 = 375 + 206.91408 = 581.9141
select is(
    public.cascade_stap3_structurele_vermindering(6000.0000, 1.0000, 3::smallint, '2024-01-01'::date),
    581.9141::numeric(18, 4),
    'T6 cat 3 laag loon: 375 + 0.1714 × 1207.20 = 581.9141'
);

-- T7: S=15000, μ=1.0 → 375 + 0 + 0.0686 × (15000-12435.31) = 375 + 175.93773 = 550.9378
select is(
    public.cascade_stap3_structurele_vermindering(15000.0000, 1.0000, 3::smallint, '2024-01-01'::date),
    550.9378::numeric(18, 4),
    'T7 cat 3 hoog loon: 375 + 0.0686 × 2564.69 = 550.9378'
);

-- T8: S=10000 (deadband), μ=1.0 → 375 + 0 + 0 = 375 (alleen forfait)
select is(
    public.cascade_stap3_structurele_vermindering(10000.0000, 1.0000, 3::smallint, '2024-01-01'::date),
    375.0000::numeric(18, 4),
    'T8 cat 3 deadband: S=10000 tussen S0 en S1 → 375 (alleen forfait)'
);


------------------------------------------------------------
-- T9 KEY: Principe IV — μ pro rata schaalt HELE R via expliciete haakjes
------------------------------------------------------------

select is(
    public.cascade_stap3_structurele_vermindering(6000.0000, 0.5000, 1::smallint, '2024-01-01'::date),
    84.4540::numeric(18, 4),
    'T9 KEY Principe IV μ pro rata: cat 1 S=6000 met μ=0.5 → 168.9080 × 0.5 = 84.4540 (bewijst dat μ hele R schaalt, NIET alleen δ-term — expliciete haakjes werken)'
);


------------------------------------------------------------
-- Boundary tests: S=S0 exact en S=S1 exact
------------------------------------------------------------

-- T10: Cat 3 S=S0=7207.20 exact, μ=1.0 → GREATEST(0, S0-S)=0 → 375 + 0 + 0 = 375
select is(
    public.cascade_stap3_structurele_vermindering(7207.2000, 1.0000, 3::smallint, '2024-01-01'::date),
    375.0000::numeric(18, 4),
    'T10 boundary S=S0 exact: cat 3 S=7207.20 → 375 (GREATEST(0, 0)=0 → laag term nul, geen hoog term)'
);

-- T11: Cat 3 S=S1=12435.31 exact, μ=1.0 → GREATEST(0, S-S1)=0 → 375 + 0 + 0 = 375
select is(
    public.cascade_stap3_structurele_vermindering(12435.3100, 1.0000, 3::smallint, '2024-01-01'::date),
    375.0000::numeric(18, 4),
    'T11 boundary S=S1 exact: cat 3 S=12435.31 → 375 (GREATEST(0, 0)=0 → hoog term nul, S >= S0 dus laag term nul)'
);


------------------------------------------------------------
-- T12: Temporele miss
------------------------------------------------------------

select is(
    public.cascade_stap3_structurele_vermindering(6000.0000, 1.0000, 1::smallint, '2023-01-01'::date),
    null::numeric(18, 4),
    'T12 temporele miss: periode 2023-01 (voor geldig_van 2024) → NULL (consistent met T-023/24/26/41)'
);


select * from finish();
ROLLBACK;
