BEGIN;
-- T-048: cascade_stap8_wagen_solidariteitsbijdrage(co2, brandstoftype, periode)
--        pure functie voor CO2-solidariteitsbijdrage patronale RSZ per bedrijfswagen.
--        Depends: param_wagen_mobiliteit (T-017 schema + T-020 seed).
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration. Bij eerste run zonder migration MOET has_function falen (Red).
--
-- Principe II data-driven: factor, correcties, indexatie én minimum uit param_wagen_mobiliteit
-- via periode temporele join. Correcties uit co2_formule_json ->> 'correctie_<brandstof>'.
-- GEEN hardcoded 9.0 factor of 768/600/990 correcties in function-body.
--
-- Formule per RSZ 2024/1:
--   maandbedrag = max(minimumbijdrage,
--                     ((co2 * factor) - correctie_per_brandstoftype) * indexatie / 12)
--   waar (factor, correctie_*, indexatie_YYYY) uit co2_formule_json op de gematchte row.
--
-- Brandstoftype-mapping voor correctie-key:
--   benzine, hybride_benzine → 'correctie_benzine' (768.0)
--   diesel, hybride_diesel   → 'correctie_diesel'  (600.0)
--   lpg                       → 'correctie_lpg'     (990.0)
--   elektrisch, waterstof, cng → geen correctie → minimum bijdrage
--
-- NULL contract (consistent met T-041, T-042):
--   Temporele join miss (onbekende periode) → NULL.
--   Cascade orchestrator T-029 detecteert NULL en throwt gestructureerde fout.

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(12);


------------------------------------------------------------
-- T1: Function existence
------------------------------------------------------------

select has_function(
    'public', 'cascade_stap8_wagen_solidariteitsbijdrage',
    array['smallint', 'text', 'date'],
    'T1: public.cascade_stap8_wagen_solidariteitsbijdrage(smallint, text, date) function exists'
);


------------------------------------------------------------
-- T2: Diesel typisch (120g/km) — formule kicks in
--     (120*9 - 600) * 1.5359 / 12 = 480 * 1.5359 / 12 = 61.4360
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(120::smallint, 'diesel', '2024-06-01'::date),
    61.4360::numeric(18, 4),
    'T2 diesel 120g: (120*9 - 600) * 1.5359 / 12 = 61.4360 (RSZ 2024/1 formule)'
);


------------------------------------------------------------
-- T3: Diesel low (82g/km, referentie-CO2) — floor bij minimumbijdrage
--     (82*9 - 600) * 1.5359 / 12 = 138 * 1.5359 / 12 = 17.6629 < 31.99 → 31.9900
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(82::smallint, 'diesel', '2024-06-01'::date),
    31.9900::numeric(18, 4),
    'T3 diesel 82g (referentie): berekend 17.6629 < 31.99 → minimum wint (bewijst max(minimum, computed))'
);


------------------------------------------------------------
-- T4: Benzine typisch (120g/km)
--     (120*9 - 768) * 1.5359 / 12 = 312 * 1.5359 / 12 = 39.9334
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(120::smallint, 'benzine', '2024-06-01'::date),
    39.9334::numeric(18, 4),
    'T4 benzine 120g: (120*9 - 768) * 1.5359 / 12 = 39.9334 (bewijst correctie_benzine differs van diesel)'
);


------------------------------------------------------------
-- T5: Benzine low (90g/km) — floor bij minimum
--     (90*9 - 768) * 1.5359 / 12 = 42 * 1.5359 / 12 = 5.3757 < 31.99 → 31.9900
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(90::smallint, 'benzine', '2024-06-01'::date),
    31.9900::numeric(18, 4),
    'T5 benzine 90g: berekend 5.3757 < 31.99 → minimum wint'
);


------------------------------------------------------------
-- T6: LPG (150g/km) — eigen correctie 990
--     (150*9 - 990) * 1.5359 / 12 = 360 * 1.5359 / 12 = 46.0770
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(150::smallint, 'lpg', '2024-06-01'::date),
    46.0770::numeric(18, 4),
    'T6 lpg 150g: (150*9 - 990) * 1.5359 / 12 = 46.0770 (bewijst correctie_lpg apart)'
);


------------------------------------------------------------
-- T7: Elektrisch — geen correctie-key → minimum only
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(0::smallint, 'elektrisch', '2024-06-01'::date),
    31.9900::numeric(18, 4),
    'T7 elektrisch: geen correctie-key voor brandstoftype → minimum bijdrage 31.9900'
);


------------------------------------------------------------
-- T8: Waterstof — minimum only
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(0::smallint, 'waterstof', '2024-06-01'::date),
    31.9900::numeric(18, 4),
    'T8 waterstof: geen correctie-key → minimum bijdrage 31.9900'
);


------------------------------------------------------------
-- T9: Hybride_diesel (150g/km) — gebruikt correctie_diesel
--     (150*9 - 600) * 1.5359 / 12 = 750 * 1.5359 / 12 = 95.9938
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(150::smallint, 'hybride_diesel', '2024-06-01'::date),
    95.9938::numeric(18, 4),
    'T9 hybride_diesel 150g: gebruikt correctie_diesel (600) → 95.9938 (bewijst hybride mapping)'
);


------------------------------------------------------------
-- T10: Hybride_benzine (90g/km) — gebruikt correctie_benzine, floor
--     (90*9 - 768) * 1.5359 / 12 = 5.3757 < 31.99 → 31.9900
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(90::smallint, 'hybride_benzine', '2024-06-01'::date),
    31.9900::numeric(18, 4),
    'T10 hybride_benzine 90g: gebruikt correctie_benzine → 5.3757 < 31.99 → minimum'
);


------------------------------------------------------------
-- T11: Temporele join miss vroeger
--      periode 2023-12-31 (voor geldig_van 2024-01-01) → NULL
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(120::smallint, 'diesel', '2023-12-31'::date),
    null::numeric(18, 4),
    'T11 temporele miss vroeger: periode 2023-12-31 → NULL (valt buiten interval [2024-01-01, ∞))'
);


------------------------------------------------------------
-- T12: co2 zeer laag met benzine — computed kan negatief, minimum floor greifs
--      co2=0 benzine: (0*9 - 768) * 1.5359 / 12 = -98.30 < 31.99 → 31.9900
------------------------------------------------------------

select is(
    public.cascade_stap8_wagen_solidariteitsbijdrage(0::smallint, 'benzine', '2024-06-01'::date),
    31.9900::numeric(18, 4),
    'T12 boundary co2=0 benzine: computed -98.30 → minimum floor wint (bewijst GREATEST met negatief)'
);


select * from finish();
ROLLBACK;
