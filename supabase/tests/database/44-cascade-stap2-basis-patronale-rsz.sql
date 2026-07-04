BEGIN;
-- T-041: cascade_stap2_basis_patronale_rsz(rsz_grondslag, status, werkgeverscategorie, periode)
--        pure functie voor basis patronale RSZ.
--        Depends: param_rsz (T-015 schema + T-018 seed + T-041 HOTFIX basisfactor NOT NULL)
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration. Bij eerste run zonder migration MOET has_function falen (Red).
--
-- Principe II data-driven: tarief én factor uit param_rsz via (status, werkgeverscategorie, periode)
-- temporele join — GEEN hardcoded 25.07% of 1.08 in function-body.
--
-- Formule:
--   basis_patronale_rsz = rsz_grondslag × basisbijdrage_pct × basisfactor_pct
--   waar (basisbijdrage_pct, basisfactor_pct) via temporele join op param_rsz
--   met p_periode >= geldig_van AND (geldig_tot IS NULL OR p_periode < geldig_tot).
--
-- NULL contract: temporele join miss → NULL. Documented behavior, cascade orchestrator
-- (T-029) detecteert en throwt gestructureerde fout. Consistent met T-023/24/26.

create extension if not exists pgtap;

select plan(10);

-- Geen contract/tenant setup nodig — function neemt numeric + text + smallint + date.
-- param_rsz seed uit T-018 al aanwezig na db reset.


------------------------------------------------------------
-- T1: Function existence
------------------------------------------------------------

select has_function(
    'public', 'cascade_stap2_basis_patronale_rsz',
    array['numeric', 'text', 'smallint', 'date'],
    'T1: public.cascade_stap2_basis_patronale_rsz(numeric, text, smallint, date) function exists'
);


------------------------------------------------------------
-- T2-T4: Bediende per werkgeverscategorie (basisfactor = 1.0000)
------------------------------------------------------------

select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 1::smallint, '2024-01-01'::date),
    1002.8000::numeric(18, 4),
    'T2 bediende cat 1: 4000 × 0.2507 × 1.0000 = 1002.8000 (RSZ instructiegids 2024/1)'
);

select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 2::smallint, '2024-01-01'::date),
    972.8000::numeric(18, 4),
    'T3 bediende cat 2 social profit: 4000 × 0.2432 × 1.0000 = 972.8000'
);

select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 3::smallint, '2024-01-01'::date),
    682.8000::numeric(18, 4),
    'T4 bediende cat 3 beschutte werkplaats: 4000 × 0.1707 × 1.0000 = 682.8000'
);


------------------------------------------------------------
-- T5-T6: Arbeider basisfactor 1.0800 (108% arbeidersgrondslag)
------------------------------------------------------------

select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'arbeider', 1::smallint, '2024-01-01'::date),
    1083.0240::numeric(18, 4),
    'T5 KEY arbeider cat 1 basisfactor: 4000 × 0.2507 × 1.0800 = 1083.0240 (bewijst 108% grondslag)'
);

select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'arbeider', 2::smallint, '2024-01-01'::date),
    1050.6240::numeric(18, 4),
    'T6 arbeider cat 2: 4000 × 0.2432 × 1.0800 = 1050.6240 (symmetrisch met T3 bediende)'
);


------------------------------------------------------------
-- T7: Categorie verschil bewijst data-driven param lookup
------------------------------------------------------------

select isnt(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 1::smallint, '2024-01-01'::date),
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 3::smallint, '2024-01-01'::date),
    'T7 data-driven categorie verschil: cat 1 (1002.80) ≠ cat 3 (682.80) — bewijst param lookup'
);


-- T8-oud was byte-identical aan T2 (fold code-review clean-code MINOR "duplication").
-- T2 dekt lower inclusive boundary al: periode = 2024-01-01 IS geldig_van. Dropped.


------------------------------------------------------------
-- T8: Temporele join UPPER-1 dag INCLUSIEF
--     periode = geldig_tot - 1 dag (2024-12-31) → matcht row
------------------------------------------------------------

select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 1::smallint, '2024-12-31'::date),
    1002.8000::numeric(18, 4),
    'T8 temporele UPPER-1 inclusief: periode = geldig_tot 2025-01-01 minus 1 dag = 2024-12-31 → matcht'
);


------------------------------------------------------------
-- T9: Temporele join UPPER boundary EXCLUSIEF
--     periode = geldig_tot (2025-01-01) → NULL (grens exclusief; 2025 heeft geen seed)
------------------------------------------------------------

select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 1::smallint, '2025-01-01'::date),
    null::numeric(18, 4),
    'T9 temporele UPPER exclusief: periode = geldig_tot 2025-01-01 → NULL (valt buiten interval [geldig_van, geldig_tot))'
);


------------------------------------------------------------
-- T10: Temporele join miss vroeger
--      periode voor geldig_van → NULL
------------------------------------------------------------

select is(
    public.cascade_stap2_basis_patronale_rsz(4000.0000, 'bediende', 1::smallint, '2023-01-01'::date),
    null::numeric(18, 4),
    'T10 temporele miss vroeger: periode 2023-01-01 (voor geldig_van 2024-01-01) → NULL'
);


select * from finish();
ROLLBACK;
