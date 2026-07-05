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

create extension if not exists pgtap;

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

-- T2: S=6000 (< S0), μ=1.0 → 0 + 0.14 × (7207.20-6000) + 0 = 169.0080
select is(
    public.cascade_stap3_structurele_vermindering(6000.0000, 1.0000, 1::smallint, '2024-01-01'::date),
    331.5153::numeric(18, 4),
    'T2 cat 1 laag loon: S=6000 → (0.14×(10797.67-6000) + 0.40×(6807.18-6000))/3 = 331.5153 (post fiscal audit: coef_b γ zeer-lage-lonen, kwartaal→maand)'
);

-- T3: S=8000 (tussen S0 en S1), μ=1.0 → 0 + 0 + 0 = 0 (deadband)
select is(
    public.cascade_stap3_structurele_vermindering(8000.0000, 1.0000, 1::smallint, '2024-01-01'::date),
    130.5579::numeric(18, 4),
    'T3 cat 1 S=8000: 0.14×max(0, 10797.67-8000)/3 = 130.5579 (deadband concept vervalt na coef_b γ herinterpretatie)'
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
    122.6072::numeric(18, 4),
    'T5 cat 2 S=6000 post fiscal audit / 3 = 122.6072'
);


------------------------------------------------------------
-- Cat 3: F=375, α=0.1714, δ=0.0686 — beide componenten
------------------------------------------------------------

-- T6: S=6000, μ=1.0 → 375 + 0.1714 × 1207.20 + 0 = 375 + 206.91408 = 581.9141
select is(
    public.cascade_stap3_structurele_vermindering(6000.0000, 1.0000, 3::smallint, '2024-01-01'::date),
    193.9714::numeric(18, 4),
    'T6 cat 3 S=6000 post fiscal audit / 3 = 193.9714'
);

-- T7: S=15000, μ=1.0 → 375 + 0 + 0.0686 × (15000-12435.31) = 375 + 175.9377 = 550.9377
select is(
    public.cascade_stap3_structurele_vermindering(15000.0000, 1.0000, 3::smallint, '2024-01-01'::date),
    125.0000::numeric(18, 4),
    'T7 cat 3 S=15000: forfait 375 / 3 = 125.0000 (S buiten alle drempel ranges na coef_b γ herinterpretatie)'
);

-- T8: S=10000 (deadband), μ=1.0 → 375 + 0 + 0 = 375 (alleen forfait)
select is(
    public.cascade_stap3_structurele_vermindering(10000.0000, 1.0000, 3::smallint, '2024-01-01'::date),
    125.0000::numeric(18, 4),
    'T8 cat 3 S=10000: forfait 375 / 3 = 125.0000 (kwartaal→maand normalisatie)'
);


------------------------------------------------------------
-- T9 KEY: Principe IV — μ pro rata schaalt HELE R via expliciete haakjes
------------------------------------------------------------

select is(
    public.cascade_stap3_structurele_vermindering(6000.0000, 0.5000, 1::smallint, '2024-01-01'::date),
    165.7576::numeric(18, 4),
    'T9 KEY Principe IV μ pro rata: cat 1 S=6000 met μ=0.5 → T2 × 0.5 = 165.7576 (bewijst dat μ hele R schaalt via expliciete haakjes)'
);


------------------------------------------------------------
-- Boundary tests: S=S0 exact en S=S1 exact
------------------------------------------------------------

-- T10: Cat 3 S=S0=7207.20 exact, μ=1.0 → GREATEST(0, S0-S)=0 → 375 + 0 + 0 = 375
select is(
    public.cascade_stap3_structurele_vermindering(7207.2000, 1.0000, 3::smallint, '2024-01-01'::date),
    125.0000::numeric(18, 4),
    'T10 cat 3 S=7207.20: forfait 375 / 3 = 125.0000'
);

-- T11: Cat 3 S=S1=12435.31 exact, μ=1.0 → GREATEST(0, S-S1)=0 → 375 + 0 + 0 = 375
select is(
    public.cascade_stap3_structurele_vermindering(12435.3100, 1.0000, 3::smallint, '2024-01-01'::date),
    125.0000::numeric(18, 4),
    'T11 cat 3 S=12435.31: forfait 375 / 3 = 125.0000'
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
