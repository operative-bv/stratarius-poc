BEGIN;
-- T-054: scenario reproducibility ref via param_snapshot_batch_id.
--        ALTER dim_scenario met NULL-able uuid kolom + helper functie.
--
-- Principe V: test-first commit.

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(6);


------------------------------------------------------------
-- T1: dim_scenario heeft param_snapshot_batch_id kolom (nullable uuid)
------------------------------------------------------------

select has_column(
    'public', 'dim_scenario', 'param_snapshot_batch_id',
    'T1a: dim_scenario.param_snapshot_batch_id kolom bestaat'
);

select col_type_is(
    'public', 'dim_scenario', 'param_snapshot_batch_id', 'uuid',
    'T1b: param_snapshot_batch_id is uuid type'
);

select col_is_null(
    'public', 'dim_scenario', 'param_snapshot_batch_id',
    'T1c: param_snapshot_batch_id is NULL-able (impliciet current default)'
);


------------------------------------------------------------
-- T2: helper get_current_snapshot_batch_id() returns NULL when leeg
------------------------------------------------------------

select is(
    public.get_current_snapshot_batch_id(),
    null::uuid,
    'T2 leeg: audit_parameter_snapshot bevat geen rijen → NULL'
);


------------------------------------------------------------
-- T3: helper returnt meest recente batch_id
--     Insert 2 snapshots met verschillende taken_at, verifieer de latest.
------------------------------------------------------------

insert into public.audit_parameter_snapshot (
    snapshot_batch_id, taken_at, reden, tabel_naam,
    rowcount, active_rowcount, distinct_bron_url_count,
    has_null_bron_url, open_ended_count, checksum
) values
    ('11111111-1111-1111-1111-111111111111'::uuid, '2024-01-01 10:00:00+00', 'test_oud',
     'param_rsz', 0, 0, 0, false, 0, 'oud'),
    ('22222222-2222-2222-2222-222222222222'::uuid, '2024-06-01 10:00:00+00', 'test_nieuw',
     'param_rsz', 0, 0, 0, false, 0, 'nieuw');

select is(
    public.get_current_snapshot_batch_id(),
    '22222222-2222-2222-2222-222222222222'::uuid,
    'T3 nieuwste wint: helper returnt snapshot met hoogste taken_at (2024-06 > 2024-01)'
);


------------------------------------------------------------
-- T4: dim_scenario kan param_snapshot_batch_id opslaan
------------------------------------------------------------

-- Setup: gebruik Demo BVBA legale_entiteit (stabiel seed uuid)
insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind, param_snapshot_batch_id)
values (
    '54540000-0000-0000-0000-000000000001'::uuid,
    'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
    'T054 test scenario',
    'what_if',
    '22222222-2222-2222-2222-222222222222'::uuid
);

select is(
    (select param_snapshot_batch_id from public.dim_scenario where scenario_id = '54540000-0000-0000-0000-000000000001'::uuid),
    '22222222-2222-2222-2222-222222222222'::uuid,
    'T4 dim_scenario.param_snapshot_batch_id opgeslagen en teruggehaald'
);


select * from finish();
ROLLBACK;
