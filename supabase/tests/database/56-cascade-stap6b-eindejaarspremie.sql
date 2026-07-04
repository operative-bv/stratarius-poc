BEGIN;
-- T-047: cascade_stap6b_eindejaarspremie(bruto, pc_id, periode)
--        pure functie voor eindejaarspremie provisie per PC.
--        Depends: param_eindejaarspremie tabel + 2024 seed.
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration. Bij eerste run zonder migration MOET has_table + has_function falen (Red).
--
-- Principe II data-driven: coefficient uit param_eindejaarspremie via (pc_id, periode)
-- temporele join.
--
-- Formule (POC-simplification):
--   maandelijkse provisie = (bruto × coefficient) / 12
--   (jaarpremie = bruto × coefficient; verdeeld over 12 maanden als accrual)
--
-- Seed 2024 (POC_UNVERIFIED — cross-check per CAO vereist):
--   PC 200 (aanvullend bedienden): coefficient 1.0000 (1 maandloon eindejaarspremie/jaar)
--   PC 302 (horeca):               coefficient 1.0000 (1 maandloon/jaar per CAO)
--
-- Gelijkstellingen skipped voor POC (uren-based per fact_prestatie). Cascade
-- productie-uitbreiding via aparte follow-up ticket.
--
-- NULL contract (consistent met sibling functies):
--   Temporele join miss (onbekende pc_id of periode) → NULL.

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(9);


------------------------------------------------------------
-- T1: Table + function existence
------------------------------------------------------------

select has_table(
    'public', 'param_eindejaarspremie',
    'T1a: public.param_eindejaarspremie table exists'
);

select has_function(
    'public', 'cascade_stap6b_eindejaarspremie',
    array['numeric', 'text', 'date'],
    'T1b: cascade_stap6b_eindejaarspremie(numeric, text, date) function exists'
);


------------------------------------------------------------
-- T2: PC 200 bediende — 4000 × 1.0 / 12 = 333.3333
------------------------------------------------------------

select is(
    public.cascade_stap6b_eindejaarspremie(4000.0000, '200', '2024-06-01'::date),
    333.3333::numeric(18, 4),
    'T2 PC 200 bediende: 4000 × 1.0000 / 12 = 333.3333 (1 maandloon per jaar)'
);


------------------------------------------------------------
-- T3: PC 302 horeca — 3000 × 1.0 / 12 = 250.0000
------------------------------------------------------------

select is(
    public.cascade_stap6b_eindejaarspremie(3000.0000, '302', '2024-06-01'::date),
    250.0000::numeric(18, 4),
    'T3 PC 302 horeca: 3000 × 1.0000 / 12 = 250.0000'
);


------------------------------------------------------------
-- T4: Lineaire schaling — 8000 × 1.0 / 12 = 666.6667
------------------------------------------------------------

select is(
    public.cascade_stap6b_eindejaarspremie(8000.0000, '200', '2024-06-01'::date),
    666.6667::numeric(18, 4),
    'T4 lineaire schaling: 8000 (2× T2) → 666.6667 (2× T2 output)'
);


------------------------------------------------------------
-- T5: Temporele miss vroeger → NULL
------------------------------------------------------------

select is(
    public.cascade_stap6b_eindejaarspremie(4000.0000, '200', '2023-12-31'::date),
    null::numeric(18, 4),
    'T5 temporele miss vroeger: periode 2023-12-31 → NULL (voor geldig_van 2024-01-01)'
);


------------------------------------------------------------
-- T6: Onbekende PC → NULL
------------------------------------------------------------

select is(
    public.cascade_stap6b_eindejaarspremie(4000.0000, '100', '2024-06-01'::date),
    null::numeric(18, 4),
    'T6 onbekende PC 100: geen param_eindejaarspremie seed → NULL'
);


------------------------------------------------------------
-- T7: LOWER boundary — periode = geldig_van INCLUSIEF
------------------------------------------------------------

select is(
    public.cascade_stap6b_eindejaarspremie(4000.0000, '200', '2024-01-01'::date),
    333.3333::numeric(18, 4),
    'T7 LOWER boundary: periode = geldig_van 2024-01-01 → matcht (half-open interval)'
);


------------------------------------------------------------
-- T8: UPPER boundary — periode = geldig_tot EXCLUSIEF → NULL
------------------------------------------------------------

select is(
    public.cascade_stap6b_eindejaarspremie(4000.0000, '200', '2025-01-01'::date),
    null::numeric(18, 4),
    'T8 UPPER exclusief: periode = geldig_tot 2025-01-01 → NULL (valt buiten [geldig_van, geldig_tot))'
);


select * from finish();
ROLLBACK;
