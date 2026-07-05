-- ================================================================
-- Cleanup: verwijder dead code
-- ================================================================
--
-- Deze objects zijn nooit in gebruik geraakt of vervangen:
--
-- 1. mart_refresh_log tabel + run_scheduled_mart_refresh functie:
--    bedoeld voor cron-gescheduled mart_loonkloof refresh, maar cron is
--    nooit actief geworden. 0 rows in tabel. Geen enkele call-site.
--
-- 2. param_extralegaal_override + resolve_extralegaal_taks:
--    per-tenant override laag voor extralegaal params. resolve_extralegaal_taks
--    wordt nergens aangeroepen (cascade functies gebruiken de reguliere
--    param_extralegaal). Feature nooit geactiveerd.
--
-- Impact op prod: geen. Deze objects raken geen enkele UI-flow.
-- ================================================================

drop function if exists public.run_scheduled_mart_refresh() cascade;
drop table if exists public.mart_refresh_log cascade;

drop function if exists public.resolve_extralegaal_taks(uuid, text, date) cascade;
drop table if exists public.param_extralegaal_override cascade;


-- ================================================================
-- create_parameter_snapshot: verwijder param_extralegaal_override uit v_tables
-- ================================================================

create or replace function public.create_parameter_snapshot(p_reden text)
    returns uuid
    language plpgsql
    security definer
    set search_path = pg_catalog, pg_temp
as $$
declare
    v_batch uuid := gen_random_uuid();
    v_tables text[] := array[
        'param_rsz','param_plafond','param_structurele_vermindering',
        'param_doelgroepvermindering','param_arbeidsduur','param_vakantiegeld',
        'param_bijzondere_bijdragen','param_sectorbijdrage','param_extralegaal',
        'param_wagen_mobiliteit','param_index','param_arbeidsongevallen',
        'param_eindejaarspremie'
    ];
    t text;
begin
    foreach t in array v_tables loop
        execute format($f$
            insert into public.audit_parameter_snapshot (
                snapshot_batch_id, reden, tabel_naam,
                rowcount, active_rowcount, distinct_bron_url_count,
                has_null_bron_url, open_ended_count,
                max_geldig_van, min_geldig_van, checksum
            )
            select $1, $2, %L,
                count(*)::int,
                count(*) filter (where geldig_tot is null or geldig_tot > current_date)::int,
                count(distinct bron_url)::int,
                coalesce(bool_or(bron_url is null), false),
                count(*) filter (where geldig_tot is null)::int,
                max(geldig_van), min(geldig_van),
                coalesce(md5(string_agg(md5(x.*::text), '' order by x.geldig_van, x.bron_url)), md5(''))
            from public.%I x
        $f$, t, t) using v_batch, p_reden;
    end loop;
    return v_batch;
end;
$$;
