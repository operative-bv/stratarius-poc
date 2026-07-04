BEGIN;
-- T-058: cascade_populatie_snapshot uitgebreid met stap 8, stap 9, en echte mu.
--
-- Principe V: test-first commit voor return-type wijziging.
--
-- Wijzigingen tov vorige versie:
--   - Nieuwe kolommen: mu numeric(6,4), stap8_wagen numeric(18,4), stap9_arbeidsongevallen numeric(18,4)
--   - Stap 3 aanroep gebruikt echte mu (via mu_van_prestatie) ipv hardcoded 1.0000
--   - totaal_patronale_kost + tco sommeren stap8 + stap9
--
-- Deze migration DROPT de oude signature en CREATE'T een nieuwe (returns TABLE kan
-- niet via CREATE OR REPLACE geherstructureerd worden in Postgres).

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(5);


------------------------------------------------------------
-- T1: Function existence (signature ongewijzigd: date, uuid, uuid)
------------------------------------------------------------

select has_function(
    'public', 'cascade_populatie_snapshot',
    array['date', 'uuid', 'uuid'],
    'T1: cascade_populatie_snapshot(date, uuid, uuid) function exists'
);


------------------------------------------------------------
-- T2: Nieuwe kolom stap8_wagen aanwezig in return-type
--     lives_ok bewijst dat query parse-t; als kolom mist -> error
------------------------------------------------------------

select lives_ok(
    $$select stap8_wagen from public.cascade_populatie_snapshot('2024-06-01'::date, null::uuid, null::uuid) limit 0$$,
    'T2: return-type bevat kolom stap8_wagen numeric(18,4)'
);


------------------------------------------------------------
-- T3: Nieuwe kolom stap9_arbeidsongevallen aanwezig in return-type
------------------------------------------------------------

select lives_ok(
    $$select stap9_arbeidsongevallen from public.cascade_populatie_snapshot('2024-06-01'::date, null::uuid, null::uuid) limit 0$$,
    'T3: return-type bevat kolom stap9_arbeidsongevallen numeric(18,4)'
);


------------------------------------------------------------
-- T4: Nieuwe kolom mu aanwezig in return-type
------------------------------------------------------------

select lives_ok(
    $$select mu from public.cascade_populatie_snapshot('2024-06-01'::date, null::uuid, null::uuid) limit 0$$,
    'T4: return-type bevat kolom mu numeric(6,4) — bewijst mu-per-contract CTE'
);


------------------------------------------------------------
-- T5: Bestaande kolommen behouden (regression guard)
--     Alle historische kolommen die de UI leest MOETEN blijven bestaan.
------------------------------------------------------------

select lives_ok(
    $$select contract_id, persoon_id, pc_id, status, werkgeverscategorie, functienaam,
             bruto, stap2_basis_rsz, stap3_vermindering, stap5_bijzondere,
             stap6_vakantiegeld, stap7_extralegaal, totaal_patronale_kost, tco
      from public.cascade_populatie_snapshot('2024-06-01'::date, null::uuid, null::uuid)
      limit 0$$,
    'T5 regression: bestaande UI-kolommen contract_id/bruto/stap2..stap7/totaal/tco behouden'
);


select * from finish();
ROLLBACK;
