BEGIN;
-- T-021: audit_parameter_snapshot + create_parameter_snapshot() reconciliation.
-- Depends on: T-015 t/m T-020 data-imports (44 data-rijen).

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(17);

set local role service_role;


------------------------------------------------------------
-- Schema shape (3 assertions)
------------------------------------------------------------

select has_table('public', 'audit_parameter_snapshot', 'audit_parameter_snapshot table exists');
select col_is_pk('public', 'audit_parameter_snapshot', 'snapshot_id', 'snapshot_id is PK');
select has_function('public', 'create_parameter_snapshot', array['text'], 'create_parameter_snapshot(text) function exists');


------------------------------------------------------------
-- Function invocation smoke (2 assertions)
------------------------------------------------------------

-- Create the first snapshot and store the batch id
create temp table t021_first_batch (batch_id uuid);
insert into t021_first_batch (batch_id)
    select public.create_parameter_snapshot('test-invoke-1');

select isnt(
    (select batch_id from t021_first_batch),
    null,
    'create_parameter_snapshot returned non-NULL uuid'
);

select is(
    (select count(*)::int from public.audit_parameter_snapshot where snapshot_batch_id = (select batch_id from t021_first_batch)),
    11,
    'first snapshot batch bevat exact 11 rijen (één per param_* tabel)'
);


------------------------------------------------------------
-- Invariant a: bron_url NOT NULL (1 assertion)
-- Constitution regel 234 vereist bron_url op elke parameterrij.
-- Snapshot MUST report has_null_bron_url = false voor alle 11 tabellen.
------------------------------------------------------------

select is(
    (select count(*)::int
     from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_first_batch)
       and has_null_bron_url = true),
    0,
    'invariant a: geen enkele tabel heeft NULL bron_url (Constitution regel 234)'
);


------------------------------------------------------------
-- Invariant c: reconciliation totals per tabel (5 spot-checks)
-- Verify actieve rijen matchen verwachte counts uit T-018/T-019/T-020 imports.
------------------------------------------------------------

select is(
    (select rowcount from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_first_batch)
       and tabel_naam = 'param_rsz'),
    6,
    'param_rsz rowcount = 6 (T-018 import)'
);

select is(
    (select rowcount from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_first_batch)
       and tabel_naam = 'param_structurele_vermindering'),
    3,
    'param_structurele_vermindering rowcount = 3 (T-018 import)'
);

select is(
    (select rowcount from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_first_batch)
       and tabel_naam = 'param_index'),
    4,
    'param_index rowcount = 4 (T-019 import)'
);

select is(
    (select rowcount from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_first_batch)
       and tabel_naam = 'param_wagen_mobiliteit'),
    1,
    'param_wagen_mobiliteit rowcount = 1 (T-020 import; open-ended blijft altijd active)'
);

select is(
    (select rowcount from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_first_batch)
       and tabel_naam = 'param_sectorbijdrage'),
    4,
    'param_sectorbijdrage rowcount = 4 (T-020 import)'
);


------------------------------------------------------------
-- Open-ended detectie (1 assertion)
-- param_wagen_mobiliteit heeft geldig_tot NULL per T-020 design.
------------------------------------------------------------

select is(
    (select open_ended_count from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_first_batch)
       and tabel_naam = 'param_wagen_mobiliteit'),
    1,
    'param_wagen_mobiliteit open_ended_count = 1 (geldig_tot NULL per T-020)'
);


------------------------------------------------------------
-- Idempotency checksum (1 assertion)
-- 2 back-to-back invocations op ongewijzigde data → identieke checksums.
------------------------------------------------------------

create temp table t021_second_batch (batch_id uuid);
insert into t021_second_batch (batch_id)
    select public.create_parameter_snapshot('test-invoke-2');

select is(
    (select checksum from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_first_batch)
       and tabel_naam = 'param_rsz'),
    (select checksum from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_second_batch)
       and tabel_naam = 'param_rsz'),
    'idempotency: back-to-back snapshots geven identieke checksums voor param_rsz (data unchanged)'
);


------------------------------------------------------------
-- Batch uniqueness (1 assertion)
------------------------------------------------------------

select isnt(
    (select batch_id from t021_first_batch),
    (select batch_id from t021_second_batch),
    'twee create_parameter_snapshot invocations geven verschillende snapshot_batch_id'
);


------------------------------------------------------------
-- Coverage: alle 11 tabellen (1 assertion)
------------------------------------------------------------

select is(
    (select count(distinct tabel_naam)::int
     from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_second_batch)),
    11,
    'batch bevat alle 11 param_* tabellen (parameter-laag coverage complete)'
);


------------------------------------------------------------
-- Coverage-drift guard (1 assertion)
-- Aantal snapshot-tabellen matcht daadwerkelijk aantal param_* tabellen in DB.
-- Vangt: iemand voegt param_12 toe zonder v_tables array update in de function.
------------------------------------------------------------

select is(
    (select count(*)::int from pg_tables where schemaname = 'public' and tablename like 'param\_%' escape '\'),
    (select count(distinct tabel_naam)::int from public.audit_parameter_snapshot
     where snapshot_batch_id = (select batch_id from t021_second_batch)),
    'snapshot dekt ALLE param_* tabellen in pg_tables (coverage-drift guard bij nieuwe param tabel)'
);


------------------------------------------------------------
-- RLS: anon cannot read (1 assertion)
------------------------------------------------------------

reset role;
set local role anon;

select is(
    (select count(*)::int from public.audit_parameter_snapshot),
    0,
    'anon reads 0 rijen (RLS to authenticated policy blokkeert)'
);


reset role;


select * from finish();
ROLLBACK;
