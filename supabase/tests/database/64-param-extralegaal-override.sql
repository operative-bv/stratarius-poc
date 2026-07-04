BEGIN;
-- T-053: tenant-scoped parameter overrides — POC scope: extralegaal.
--   Nieuwe tabel param_extralegaal_override met owning_account_id + effective-
--   dated overrides. Helper resolve_extralegaal_taks() returnt tenant-override
--   met fallback naar globale param_extralegaal.
--
-- Sibling param tabellen (sectorbijdrage, wagen_mobiliteit) volgen hetzelfde
-- patroon; aparte tickets als er tenant-behoefte ontstaat.

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(7);


------------------------------------------------------------
-- T1: Tabel + helper function bestaan
------------------------------------------------------------

select has_table(
    'public', 'param_extralegaal_override',
    'T1a: param_extralegaal_override tabel bestaat'
);

select has_function(
    'public', 'resolve_extralegaal_taks',
    array['uuid', 'text', 'date'],
    'T1b: resolve_extralegaal_taks(uuid, text, date) function exists'
);


------------------------------------------------------------
-- T2: Fallback naar globaal — geen override → globale taks_pct.
--     Global groepsverzekering taks_pct = 0.1326 uit T-020 seed.
------------------------------------------------------------

select is(
    public.resolve_extralegaal_taks(
        'a1111111-1111-1111-1111-111111111111'::uuid,
        'groepsverzekering',
        '2024-06-01'::date
    ),
    0.1326::numeric(6, 4),
    'T2 fallback naar globaal: geen override → 0.1326 (T-020 seed groepsverzekering)'
);


------------------------------------------------------------
-- T3: Tenant-override wint van globaal.
--     Insert override voor Demo BVBA groepsverzekering met andere taks_pct.
------------------------------------------------------------

insert into public.param_extralegaal_override
    (owning_account_id, voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url, bron_document)
values
    ('a1111111-1111-1111-1111-111111111111'::uuid,
     'groepsverzekering',
     '2024-01-01', '2025-01-01',
     500000.0000, 0.0800,
     'test://t053_demo_override',
     'T053 test — Demo BVBA groepsverzekering tenant-override 8%');

select is(
    public.resolve_extralegaal_taks(
        'a1111111-1111-1111-1111-111111111111'::uuid,
        'groepsverzekering',
        '2024-06-01'::date
    ),
    0.0800::numeric(6, 4),
    'T3 override wint: Demo BVBA krijgt 0.0800 ipv globale 0.1326 (override active)'
);


------------------------------------------------------------
-- T4: Andere tenant valt terug op globaal (override is per-tenant).
--     Gebruik seed test-account 'a0000000-...' (personal, maar owning_account
--     lookup is per account_id regardless of personal/team voor deze test).
------------------------------------------------------------

select is(
    public.resolve_extralegaal_taks(
        'a0000000-0000-0000-0000-000000000001'::uuid,
        'groepsverzekering',
        '2024-06-01'::date
    ),
    0.1326::numeric(6, 4),
    'T4 andere tenant: geen override voor a0000000 → globale 0.1326 (per-tenant scoping)'
);


------------------------------------------------------------
-- T5: Temporele join — override buiten periode telt niet.
--     Vraag voor 2023-12-31 — vóór override.geldig_van 2024-01-01 → globaal.
------------------------------------------------------------

select is(
    public.resolve_extralegaal_taks(
        'a1111111-1111-1111-1111-111111111111'::uuid,
        'groepsverzekering',
        '2023-12-31'::date
    ),
    null::numeric(6, 4),
    'T5 temporele buiten override én globaal geldig_van (beide gestart 2024): NULL'
);


------------------------------------------------------------
-- T6: Onbekend voordeeltype → NULL.
------------------------------------------------------------

select is(
    public.resolve_extralegaal_taks(
        'a1111111-1111-1111-1111-111111111111'::uuid,
        'niet_bestaand',
        '2024-06-01'::date
    ),
    null::numeric(6, 4),
    'T6 onbekend voordeeltype → NULL'
);


select * from finish();
ROLLBACK;
