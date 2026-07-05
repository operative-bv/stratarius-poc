BEGIN;
-- T-049: cascade_stap9_arbeidsongevallen(rsz_grondslag, pc_id, periode)
--        pure functie voor arbeidsongevallenverzekering per PC.
--        Depends: param_arbeidsongevallen tabel + 2024 seed.
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration. Bij eerste run zonder migration MOET has_table + has_function falen (Red).
--
-- Principe II data-driven: tarief_pct en min_premie uit param_arbeidsongevallen via
-- (pc_id, periode) temporele join.
--
-- Formule:
--   maandbedrag = max(min_premie / 12, rsz_grondslag × tarief_pct)
--
-- Seed 2024 (POC_UNVERIFIED — cross-check met verzekeringsmaatschappij vereist):
--   PC 200 (aanvullend bedienden, laag risico): tarief 0.0030 (0.30%), min_premie 60/jaar
--   PC 302 (horeca, hoger risico):              tarief 0.0060 (0.60%), min_premie 60/jaar
--
-- NULL contract (consistent met T-041, T-042, T-048):
--   Temporele join miss (onbekende pc_id of periode) → NULL.
--   Cascade orchestrator T-029 detecteert NULL en throwt gestructureerde fout.

create extension if not exists pgtap;

select plan(11);


------------------------------------------------------------
-- T1: Table + function existence
------------------------------------------------------------

select has_table(
    'public', 'param_arbeidsongevallen',
    'T1a: public.param_arbeidsongevallen table exists'
);

select has_function(
    'public', 'cascade_stap9_arbeidsongevallen',
    array['numeric', 'text', 'date'],
    'T1b: cascade_stap9_arbeidsongevallen(numeric, text, date) function exists'
);


------------------------------------------------------------
-- T2: PC 200 basic — 4000 × 0.0030 = 12.0000 (boven min-floor 5.00)
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(4000.0000, '200', '2024-06-01'::date),
    12.0000::numeric(18, 4),
    'T2 PC 200 (bedienden): 4000 × 0.0030 = 12.0000 (POC_UNVERIFIED tarief 0.30%)'
);


------------------------------------------------------------
-- T3: PC 302 basic — 4000 × 0.0060 = 24.0000 (hoger risico horeca)
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(4000.0000, '302', '2024-06-01'::date),
    24.0000::numeric(18, 4),
    'T3 PC 302 (horeca): 4000 × 0.0060 = 24.0000 (bewijst PC-differentiatie)'
);


------------------------------------------------------------
-- T4: PC 200 min-floor — 1000 × 0.0030 = 3.00 < 5.00 → 5.0000
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(1000.0000, '200', '2024-06-01'::date),
    5.0000::numeric(18, 4),
    'T4 PC 200 min-floor: berekend 3.00 < 60/12=5.00 → min_premie wint (bewijst GREATEST met min/12)'
);


------------------------------------------------------------
-- T5: PC 302 min-floor — 500 × 0.0060 = 3.00 < 5.00 → 5.0000
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(500.0000, '302', '2024-06-01'::date),
    5.0000::numeric(18, 4),
    'T5 PC 302 min-floor: berekend 3.00 < 5.00 → minimum wint'
);


------------------------------------------------------------
-- T6: Temporele miss vroeger — periode 2023 → NULL
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(4000.0000, '200', '2023-12-31'::date),
    null::numeric(18, 4),
    'T6 temporele miss vroeger: periode 2023-12-31 → NULL (voor geldig_van 2024-01-01)'
);


------------------------------------------------------------
-- T7: Onbekende PC — geen seed → NULL
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(4000.0000, '100', '2024-06-01'::date),
    null::numeric(18, 4),
    'T7 onbekende PC 100: geen param_arbeidsongevallen seed → NULL (temporele miss patroon)'
);


------------------------------------------------------------
-- T8: LOWER boundary — periode = geldig_van (2024-01-01) INCLUSIEF
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(4000.0000, '200', '2024-01-01'::date),
    12.0000::numeric(18, 4),
    'T8 LOWER boundary: periode = geldig_van 2024-01-01 → matcht (half-open interval)'
);


------------------------------------------------------------
-- T9: Temporele boundary 2024↔2025 — 2025-param toegevoegd via
--     fiscal audit (20260705160000), tarief bleef zelfde voor PC 200
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(4000.0000, '200', '2025-01-01'::date),
    12.0000::numeric(18, 4),
    'T9 boundary 2024↔2025: periode 2025-01-01 → 2025-param (tarief PC 200 bleef 0.30%)'
);


------------------------------------------------------------
-- T10: Grote grondslag — bewijst tarief × grondslag schaalt lineair
--      10000 × 0.0060 = 60.0000 (PC 302, 2.5× de T3 grondslag)
------------------------------------------------------------

select is(
    public.cascade_stap9_arbeidsongevallen(10000.0000, '302', '2024-06-01'::date),
    60.0000::numeric(18, 4),
    'T10 lineaire schaling: 10000 × 0.0060 = 60.0000 (2.5× T3 grondslag = 2.5× resultaat)'
);


select * from finish();
ROLLBACK;
