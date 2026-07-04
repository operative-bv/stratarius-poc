BEGIN;
-- T-056: cascade_populatie_snapshot subset filters via p_filters jsonb.
--        Nieuwe signature (date, uuid, jsonb) vervangt (date, uuid, uuid).
--        Filter keys (allemaal optioneel):
--          pc_ids: text[] — filter op paritair comité
--          statussen: text[] — arbeider|bediende
--          gewesten: text[] — vlaanderen|wallonie|brussel
--          functie_ids: uuid[] — vervangt oude p_functie_id
--          ancienniteit_min_jaren, ancienniteit_max_jaren: numeric
--          leeftijd_min, leeftijd_max: int
--
-- Principe V: test-first commit.

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(5);


------------------------------------------------------------
-- T1: nieuwe signature (date, uuid, jsonb)
------------------------------------------------------------

select has_function(
    'public', 'cascade_populatie_snapshot',
    array['date', 'uuid', 'jsonb'],
    'T1: cascade_populatie_snapshot(date, uuid, jsonb) function exists'
);


------------------------------------------------------------
-- T2: oude signature (date, uuid, uuid) bestaat NIET meer
------------------------------------------------------------

select hasnt_function(
    'public', 'cascade_populatie_snapshot',
    array['date', 'uuid', 'uuid'],
    'T2 oude signature (date, uuid, uuid) DROPPED — voorkomt stale callers'
);


------------------------------------------------------------
-- T3: default filters = leeg jsonb → geen filter toegepast
--     lives_ok bewijst dat call zonder filters parseert.
------------------------------------------------------------

select lives_ok(
    $$select 1 from public.cascade_populatie_snapshot('2024-06-01'::date) limit 1$$,
    'T3 call zonder filters (default jsonb) parseert en runt'
);


------------------------------------------------------------
-- T4: filters met pc_ids array
------------------------------------------------------------

select lives_ok(
    $$select 1 from public.cascade_populatie_snapshot(
        '2024-06-01'::date,
        null::uuid,
        '{"pc_ids":["200","302"]}'::jsonb
    ) limit 1$$,
    'T4 filters.pc_ids array wordt geaccepteerd'
);


------------------------------------------------------------
-- T5: complex filter combinatie
------------------------------------------------------------

select lives_ok(
    $$select 1 from public.cascade_populatie_snapshot(
        '2024-06-01'::date,
        null::uuid,
        '{"statussen":["bediende"],"gewesten":["vlaanderen"],"leeftijd_min":25,"leeftijd_max":65,"ancienniteit_min_jaren":0,"ancienniteit_max_jaren":40}'::jsonb
    ) limit 1$$,
    'T5 complex filter combinatie: statussen+gewesten+leeftijd+ancienniteit'
);


select * from finish();
ROLLBACK;
