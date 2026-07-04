-- T-031: Quarterly scheduled refresh voor mart_loonkloof via pg_cron
--
-- Ontwerp:
--   1. mart_refresh_log tabel — audit trail per refresh-poging (manual + scheduled)
--   2. run_scheduled_mart_refresh() — SECURITY DEFINER met 3-attempts retry (exponential backoff 5s/15s/45s)
--   3. pg_cron job "mart-loonkloof-quarterly-refresh" op 1e dag van elk kwartaal 02:00 UTC
--   4. refresh_mart_loonkloof() (T-032) blijft manual entry point maar logt nu ook
--
-- Alleen scheduler-context mag naar mart_refresh_log INSERT'en (RPC's) — SELECT open voor authenticated.

create extension if not exists pg_cron with schema extensions;

-- Audit log per refresh-poging
create table if not exists public.mart_refresh_log (
    log_id uuid primary key default gen_random_uuid(),
    mart_name text not null,
    kind text not null check (kind in ('manual', 'scheduled')),
    attempt_number smallint not null default 1 check (attempt_number between 1 and 3),
    started_at timestamptz not null default now(),
    completed_at timestamptz null,
    success boolean null,
    error_message text null,
    rowcount_before bigint null,
    rowcount_after bigint null,
    initiator uuid null,
    rechtsgrondslag text null
);

create index if not exists mart_refresh_log_mart_started_idx
    on public.mart_refresh_log (mart_name, started_at desc);

comment on table public.mart_refresh_log is
    'Audit trail voor materialized-view refreshes (manual via RPC + scheduled via pg_cron). 3 pogingen exponential backoff (5s/15s/45s) — retry-metadata via attempt_number.';

alter table public.mart_refresh_log enable row level security;
grant select on public.mart_refresh_log to authenticated;

drop policy if exists mart_refresh_log_read on public.mart_refresh_log;
create policy mart_refresh_log_read on public.mart_refresh_log
    for select to authenticated using (true);

-- Scheduled refresh met 3-attempts exponential backoff
create or replace function public.run_scheduled_mart_refresh()
    returns void
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_attempt int := 0;
    v_max_attempts int := 3;
    v_delay int := 5;
    v_success boolean := false;
    v_rowcount_before bigint;
    v_rowcount_after bigint;
    v_log_id uuid;
    v_err text;
begin
    while v_attempt < v_max_attempts and not v_success loop
        v_attempt := v_attempt + 1;

        select count(*) into v_rowcount_before from public.mart_loonkloof;

        insert into public.mart_refresh_log
            (mart_name, kind, attempt_number, started_at, rowcount_before, rechtsgrondslag)
        values
            ('mart_loonkloof', 'scheduled', v_attempt, now(), v_rowcount_before,
             'kwartaal_refresh_pg_cron')
        returning log_id into v_log_id;

        begin
            refresh materialized view concurrently public.mart_loonkloof;
            v_success := true;

            select count(*) into v_rowcount_after from public.mart_loonkloof;

            update public.mart_refresh_log
            set completed_at = now(),
                success = true,
                rowcount_after = v_rowcount_after
            where log_id = v_log_id;

        exception when others then
            v_err := SQLERRM;

            update public.mart_refresh_log
            set completed_at = now(),
                success = false,
                error_message = v_err
            where log_id = v_log_id;

            if v_attempt < v_max_attempts then
                perform pg_sleep(v_delay);
                v_delay := v_delay * 3;  -- exponential: 5s → 15s → 45s
            end if;
        end;
    end loop;
end;
$$;

comment on function public.run_scheduled_mart_refresh() is
    'pg_cron entry point voor kwartaal-refresh mart_loonkloof. 3 pogingen exponential backoff. Elke poging krijgt eigen mart_refresh_log rij. Nooit direct aangeroepen door user-RPC — voor manual gebruik refresh_mart_loonkloof(text).';

revoke execute on function public.run_scheduled_mart_refresh() from public;
-- Alleen postgres role (pg_cron loopt hier) mag deze aanroepen — authenticated gebruikers doen manual RPC

-- Update manual refresh RPC om ook te loggen
create or replace function public.refresh_mart_loonkloof(
    p_rechtsgrondslag text
)
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_initiator uuid;
    v_log_id uuid;
    v_rowcount_before bigint;
    v_rowcount_after bigint;
    v_refreshed_at timestamptz;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'refresh_mart_loonkloof: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'refresh_mart_loonkloof: p_rechtsgrondslag is verplicht (audit trail)'
            using errcode = '22023';
    end if;

    select count(*) into v_rowcount_before from public.mart_loonkloof;

    insert into public.mart_refresh_log
        (mart_name, kind, attempt_number, started_at, rowcount_before, initiator, rechtsgrondslag)
    values
        ('mart_loonkloof', 'manual', 1, now(), v_rowcount_before, v_initiator, p_rechtsgrondslag)
    returning log_id into v_log_id;

    refresh materialized view concurrently public.mart_loonkloof;
    v_refreshed_at := now();

    select count(*) into v_rowcount_after from public.mart_loonkloof;

    update public.mart_refresh_log
    set completed_at = v_refreshed_at,
        success = true,
        rowcount_after = v_rowcount_after
    where log_id = v_log_id;

    return jsonb_build_object(
        'log_id', v_log_id,
        'refreshed_at', v_refreshed_at,
        'initiator', v_initiator,
        'rechtsgrondslag', p_rechtsgrondslag,
        'kind', 'manual',
        'rowcount_before', v_rowcount_before,
        'rowcount_after', v_rowcount_after
    );
end;
$$;

comment on function public.refresh_mart_loonkloof(text) is
    'Manual refresh RPC voor mart_loonkloof. Logt naar mart_refresh_log (kind=manual). SECURITY DEFINER met authenticated + rechtsgrondslag guards. Returns JSONB metadata incl log_id.';

revoke execute on function public.refresh_mart_loonkloof(text) from public;
grant execute on function public.refresh_mart_loonkloof(text) to authenticated;

-- Schedule: 1e dag van Jan/Apr/Jul/Oct om 02:00 UTC (rustig moment, na maandeinde payroll runs)
-- Onschadelijk om te unschedule + reschedule; idempotent guard.
do $$
begin
    if exists (select 1 from cron.job where jobname = 'mart-loonkloof-quarterly-refresh') then
        perform cron.unschedule('mart-loonkloof-quarterly-refresh');
    end if;
    perform cron.schedule(
        'mart-loonkloof-quarterly-refresh',
        '0 2 1 1,4,7,10 *',
        $refresh$select public.run_scheduled_mart_refresh();$refresh$
    );
end $$;
