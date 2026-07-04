BEGIN;
-- T-055: create_populatie_loonkost RPC — populatie write path naar fact_loonkost.
--        Enumereert contracten in tenant via cascade_populatie_snapshot,
--        schrijft 7 kostenblok rows per contract, idempotent via ON CONFLICT.
--
-- Principe V: test-first commit.

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(6);


------------------------------------------------------------
-- T1: Function existence
------------------------------------------------------------

select has_function(
    'public', 'create_populatie_loonkost',
    array['date', 'uuid', 'jsonb'],
    'T1: create_populatie_loonkost(date, uuid, jsonb) function exists'
);


------------------------------------------------------------
-- T2: Return type is jsonb (via lives_ok + explicit cast)
------------------------------------------------------------

select lives_ok(
    $$select (public.create_populatie_loonkost(
        '2024-06-01'::date,
        '11111111-1111-1111-1111-111111111111'::uuid
    ))::jsonb$$,
    'T2 return-type jsonb — call met baseline scenario succeeds'
);


------------------------------------------------------------
-- T3: fact_loonkost rijen zijn geschreven — 7 kostenblokken per contract in scope.
--     Demo BVBA heeft 27 contracten in seed → 27 × 7 = 189 rijen.
------------------------------------------------------------

-- Wis vorige inserts uit T2 om schone count te krijgen.
delete from public.fact_loonkost
where scenario_id = '11111111-1111-1111-1111-111111111111'::uuid
  and periode = '2024-06-01'::date;

-- Roep opnieuw aan.
select public.create_populatie_loonkost(
    '2024-06-01'::date,
    '11111111-1111-1111-1111-111111111111'::uuid
);

select is(
    (select count(*)::int from public.fact_loonkost
     where scenario_id = '11111111-1111-1111-1111-111111111111'::uuid
       and periode = '2024-06-01'::date),
    189,
    'T3 aantal rijen: 27 contracten × 7 kostenblokken = 189 rows in fact_loonkost'
);


------------------------------------------------------------
-- T4: Alle 7 kostenblokken aanwezig per contract.
------------------------------------------------------------

select is(
    (select array_agg(distinct kostenblok order by kostenblok)::text[] from public.fact_loonkost
     where scenario_id = '11111111-1111-1111-1111-111111111111'::uuid
       and periode = '2024-06-01'::date),
    array['arbeidsongevallen','bruto','ejp','extralegaal','vakantiegeld','wagen_tco','werkgevers_rsz']::text[],
    'T4 distinct kostenblokken: alle 7 canonieke waardes aanwezig'
);


------------------------------------------------------------
-- T5: Idempotency — herhaalde call schrijft geen dubbele rows,
--     werkt via ON CONFLICT DO UPDATE.
------------------------------------------------------------

select public.create_populatie_loonkost(
    '2024-06-01'::date,
    '11111111-1111-1111-1111-111111111111'::uuid
);

select is(
    (select count(*)::int from public.fact_loonkost
     where scenario_id = '11111111-1111-1111-1111-111111111111'::uuid
       and periode = '2024-06-01'::date),
    189,
    'T5 idempotent: 2e call houdt aantal op 189 (ON CONFLICT DO UPDATE, geen dubbele inserts)'
);


------------------------------------------------------------
-- T6: Return payload bevat rowcount, snapshot_batch_id en run_at.
------------------------------------------------------------

select ok(
    (public.create_populatie_loonkost('2024-06-01'::date, '11111111-1111-1111-1111-111111111111'::uuid))
    ?& array['rowcount', 'snapshot_batch_id', 'run_at'],
    'T6 return payload jsonb bevat keys rowcount + snapshot_batch_id + run_at'
);


select * from finish();
ROLLBACK;
