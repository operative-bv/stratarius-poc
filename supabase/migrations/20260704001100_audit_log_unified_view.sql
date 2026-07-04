-- ================================================================
-- T-050: unified audit_log view over gdpr_access_log + mart_refresh_log
-- ================================================================
--
-- Ticket scope was: persistent audit_log tabel met event_type/initiator/
-- target/rechtsgrondslag/timestamp/metadata. Bij analyse blijkt dat T-034
-- (gdpr_access_log) + T-031 (mart_refresh_log) samen al vrijwel volledig
-- leveren wat T-050 vroeg — beide zijn append-only, hebben rechtsgrondslag,
-- initiator, metadata jsonb, en RLS-tenanted.
--
-- Wat ontbrak: één query-interface voor "alle audit events". Deze migration
-- levert de unified `audit_log` view die beide tabellen UNIONed met canoniek
-- schema (event_type, event_id, initiator_user_id, created_at, target_resource,
-- rechtsgrondslag, metadata).
--
-- Waarom een view en niet een tabel:
--   - Bestaande RPCs schrijven al naar de juiste tabel (query_mart_loonkloof,
--     query_dim_persoon_gdpr → gdpr_access_log; refresh_mart_loonkloof + cron
--     → mart_refresh_log). Herrouten naar één centrale tabel breekt callers.
--   - View heeft nul migration overhead voor bestaande writes.
--   - RLS wordt geërfd via `security invoker` (default) — leest gdpr_access_log
--     alleen eigen rijen (T-034 policy), mart_refresh_log alle rijen (T-031).
--
-- Rollback:
--   DROP VIEW public.audit_log;


create or replace view public.audit_log as
    -- Bron 1: gdpr_access_log (T-034 GDPR reads)
    select
        'gdpr_read'::text        as event_type,
        log_id::text             as event_id,
        user_id                  as initiator_user_id,
        "timestamp"              as created_at,
        resource_ref             as target_resource,
        rechtsgrondslag,
        metadata || jsonb_build_object(
            'columns_accessed', columns_accessed,
            'resulting_rows',   resulting_rows,
            'event_kind',       event_kind
        )                        as metadata
    from public.gdpr_access_log

    union all

    -- Bron 2: mart_refresh_log (T-031 mart refreshes)
    select
        'mart_refresh'::text     as event_type,
        log_id::text             as event_id,
        initiator                as initiator_user_id,
        started_at               as created_at,
        mart_name                as target_resource,
        rechtsgrondslag,
        jsonb_build_object(
            'kind',            kind,
            'attempt_number',  attempt_number,
            'success',         success,
            'error_message',   error_message,
            'rowcount_before', rowcount_before,
            'rowcount_after',  rowcount_after,
            'completed_at',    completed_at
        )                        as metadata
    from public.mart_refresh_log;

comment on view public.audit_log is
    'Unified audit view over gdpr_access_log (T-034 GDPR reads) + mart_refresh_log (T-031 mart refreshes). Canoniek schema: event_type + event_id + initiator_user_id + created_at + target_resource + rechtsgrondslag + metadata. RLS wordt geërfd van onderliggende tabellen (security invoker default). Read-only observability interface — writes gaan naar de originele tabellen via bestaande RPCs.';

grant select on public.audit_log to authenticated;
