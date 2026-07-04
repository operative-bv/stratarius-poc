BEGIN;
-- T-023: uurloon_van_maandloon(maandloon, pc_id, periode) pure functie.
-- Depends on: param_arbeidsduur (T-017) + T-019 imports voor PC 111, 124, 200, 302.
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration met de function. Bij eerste run zonder migration MOET dit falen
-- (has_function faalt → Red). Na migration: alle 10 assertions slagen (Green).
--
-- Formule (Belgische conventie, PDF Laag 3):
--   uurloon = (maandloon × 3) / (13 × gemiddelde_wekelijkse_uren)
--   waar gemiddelde_wekelijkse_uren via temporele join op param_arbeidsduur (pc_id, periode).
--
-- Principe IV: uses fte_breuk semantisch (uurloon normaliseert BELONING). μ niet betrokken.
--   Deeltijds/tijdskrediet grensgevallen zitten CALLER-SIDE, niet in deze function.

create extension if not exists pgtap;

select plan(10);


------------------------------------------------------------
-- Function existence (1 assertion)
------------------------------------------------------------

select has_function(
    'public', 'uurloon_van_maandloon',
    array['numeric', 'text', 'date'],
    'public.uurloon_van_maandloon(numeric, text, date) function exists'
);


------------------------------------------------------------
-- Sanity: modale PC 200 (aanvullend bedienden, 38u/week)
------------------------------------------------------------
-- Formule: (4000 × 3) / (13 × 38) = 12000 / 494 = 24.29149797... → numeric(18,4) = 24.2915

select is(
    public.uurloon_van_maandloon(4000.0000, '200', '2024-03-01'),
    24.2915::numeric(18,4),
    'PC 200 (38u/week) maandloon 4000 → uurloon 24.2915 (Belgische conventie 13 maanden = 52 weken; RSZ instructiegids 2024/1)'
);


------------------------------------------------------------
-- PC 124 outlier (bouw, 40u/week nominaal)
------------------------------------------------------------
-- Formule: (4000 × 3) / (13 × 40) = 12000 / 520 = 23.076923... → numeric(18,4) = 23.0769

select is(
    public.uurloon_van_maandloon(4000.0000, '124', '2024-03-01'),
    23.0769::numeric(18,4),
    'PC 124 (40u/week bouw) maandloon 4000 → uurloon 23.0769 (lager door hogere ref-uren)'
);


------------------------------------------------------------
-- PC 111 (metaal 38u/week) — modale sanity dubbele check
------------------------------------------------------------

select is(
    public.uurloon_van_maandloon(4000.0000, '111', '2024-03-01'),
    24.2915::numeric(18,4),
    'PC 111 (38u/week metaal) idem PC 200 — modale sanity check (twee PCs zelfde ref-uren, zelfde uurloon)'
);


------------------------------------------------------------
-- Zero maandloon edge
------------------------------------------------------------

select is(
    public.uurloon_van_maandloon(0.0000, '200', '2024-03-01'),
    0.0000::numeric(18,4),
    'maandloon 0 → uurloon 0 (formule respecteert nul, geen div-by-zero want deler is param-uren > 0)'
);


------------------------------------------------------------
-- Cross-precision — small maandloon 1000
------------------------------------------------------------
-- Formule: (1000 × 3) / (13 × 38) = 3000 / 494 = 6.07287449... → numeric(18,4) = 6.0729

select is(
    public.uurloon_van_maandloon(1000.0000, '200', '2024-03-01'),
    6.0729::numeric(18,4),
    'PC 200 kleine maandloon 1000 → uurloon 6.0729 (proportionele scaling; dekt deeltijds numeriek via maandloon-verlaging)'
);


------------------------------------------------------------
-- Temporele lookup miss — nonexistent PC → NULL
------------------------------------------------------------

select is(
    public.uurloon_van_maandloon(4000.0000, 'nonexistent_pc', '2024-03-01'),
    null::numeric(18,4),
    'nonexistent pc_id → NULL (temporele join miss; caller detecteert en throwt gestructureerde fout per FR-016)'
);


------------------------------------------------------------
-- Cross-period miss — pre-import 2023 → NULL
------------------------------------------------------------

select is(
    public.uurloon_van_maandloon(4000.0000, '200', '2023-01-01'),
    null::numeric(18,4),
    'periode 2023-01-01 voor param_arbeidsduur.geldig_van 2024-01-01 → NULL (temporele lookup miss)'
);


------------------------------------------------------------
-- Determinisme (2 assertions)
------------------------------------------------------------

select is(
    public.uurloon_van_maandloon(4000.0000, '200', '2024-03-01'),
    public.uurloon_van_maandloon(4000.0000, '200', '2024-03-01'),
    'determinisme: 2 opeenvolgende calls met identieke inputs → identieke output (STABLE PARALLEL SAFE)'
);

select is(
    public.uurloon_van_maandloon(4000.0000, '200', '2024-03-01'),
    public.uurloon_van_maandloon(4000.0000, '200', '2024-06-01'),
    'determinisme: zelfde uurloon binnen dezelfde geldig_van/geldig_tot periode (2024-01-01 → 2025-01-01)'
);


select * from finish();
ROLLBACK;
