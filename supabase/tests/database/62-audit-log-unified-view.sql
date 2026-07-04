BEGIN;
-- T-050: unified audit_log view.
--   Consolideert gdpr_access_log (T-034 reads) + mart_refresh_log (T-031 refreshes)
--   in één query-interface met canonieke event_type/target_resource/metadata schema.

create extension if not exists pgtap;

select plan(4);


------------------------------------------------------------
-- T1: view exists
------------------------------------------------------------

select has_view(
    'public', 'audit_log',
    'T1: public.audit_log unified view exists'
);


------------------------------------------------------------
-- T2: view kolommen aanwezig
------------------------------------------------------------

select columns_are(
    'public'::name, 'audit_log'::name,
    array['event_type', 'event_id', 'initiator_user_id', 'created_at', 'target_resource', 'rechtsgrondslag', 'metadata']::name[],
    'T2: view heeft canonieke kolommen event_type/event_id/initiator_user_id/created_at/target_resource/rechtsgrondslag/metadata'
);


------------------------------------------------------------
-- T3: mart_refresh event zichtbaar via view.
--   Insert een test-refresh log rij → view returnt met event_type='mart_refresh'.
------------------------------------------------------------

insert into public.mart_refresh_log
    (mart_name, kind, attempt_number, started_at, rechtsgrondslag)
values
    ('mart_test', 'manual', 1, '2024-06-01 10:00:00+00', 'T050_test');

select is(
    (select event_type from public.audit_log
     where target_resource = 'mart_test'
       and rechtsgrondslag = 'T050_test'
     limit 1),
    'mart_refresh',
    'T3 mart_refresh_log rij verschijnt als event_type=mart_refresh in audit_log view'
);


------------------------------------------------------------
-- T4: gdpr_access_log rij zichtbaar via view (BYPASS RLS als postgres).
------------------------------------------------------------

insert into public.gdpr_access_log
    (user_id, resource_ref, columns_accessed, rechtsgrondslag, resulting_rows, event_kind)
values
    ('00000000-0000-0000-0000-000000000001'::uuid, 'test_resource',
     array['col_a'], 'T050_test_gdpr', 1, 'read');

select is(
    (select event_type from public.audit_log
     where target_resource = 'test_resource'
       and rechtsgrondslag = 'T050_test_gdpr'
     limit 1),
    'gdpr_read',
    'T4 gdpr_access_log rij verschijnt als event_type=gdpr_read in audit_log view'
);


select * from finish();
ROLLBACK;
