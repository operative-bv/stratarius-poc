BEGIN;
-- ISS-076: cascade_populatie_snapshot volledige totaal_patronale_kost + tco.
--
-- Fix T-058 gap:
--   1. cascade_stap4_doelgroepverminderingen wordt nu aangeroepen (was skipped).
--   2. stap4_doelgroep en stap7_extralegaal worden nu in totaal en tco gesommeerd
--      (stap7 was returned maar niet in totaal — pre-existing bug).
--
-- Principe V: test-first commit. Nieuwe kolom stap4_doelgroep + regression op T-058 kolommen.

create extension if not exists pgtap;

select plan(3);


------------------------------------------------------------
-- T1: Function existence (signature onaangeraakt: date, uuid, uuid)
------------------------------------------------------------

select has_function(
    'public', 'cascade_populatie_snapshot',
    array['date', 'uuid', 'jsonb'],
    'T1: cascade_populatie_snapshot(date, uuid, jsonb) function exists'
);


------------------------------------------------------------
-- T2: Nieuwe kolom stap4_doelgroep aanwezig in return-type
------------------------------------------------------------

select lives_ok(
    $$select stap4_doelgroep from public.cascade_populatie_snapshot('2024-06-01'::date, null::uuid, '{}'::jsonb) limit 0$$,
    'T2: return-type bevat kolom stap4_doelgroep numeric(18,4)'
);


------------------------------------------------------------
-- T3: Alle T-058 kolommen behouden (regression guard)
------------------------------------------------------------

select lives_ok(
    $$select contract_id, persoon_id, pc_id, status, werkgeverscategorie, functienaam,
             mu, bruto, stap2_basis_rsz, stap3_vermindering, stap4_doelgroep,
             stap5_bijzondere, stap6_vakantiegeld, stap7_extralegaal,
             stap8_wagen, stap9_arbeidsongevallen, totaal_patronale_kost, tco
      from public.cascade_populatie_snapshot('2024-06-01'::date, null::uuid, '{}'::jsonb)
      limit 0$$,
    'T3 regression: alle T-058 kolommen + nieuwe stap4_doelgroep behouden'
);


select * from finish();
ROLLBACK;
