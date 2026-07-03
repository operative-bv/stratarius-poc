-- ================================================================
-- T-021: Parameter-snapshot audit hook + reconciliation
-- ================================================================
--
-- Implementeert Constitution v1.0.1 regels 291-293:
--   "Parameter-snapshot audit: bij elke bulk-parameter-import wordt een
--    snapshot-commit gemaakt (parameter-diff + bron-URL's) voor auditbaarheid
--    en reproduceerbaarheid."
--
-- En Principe III MUST (regel 127): rekencascade is deterministisch —
-- gegeven identieke input feiten en parametersnapshot, identieke output.
--
-- Design:
--   - `audit_parameter_snapshot` table (per-tabel rijen per snapshot batch)
--   - `create_parameter_snapshot(reden)` plpgsql SECURITY DEFINER function
--     loopt door alle 11 param_* tabellen en insert één rij per tabel
--   - GRANT EXECUTE alleen aan service_role (voorkomt spam van authenticated)
--   - Dynamic SQL via format(%I, %L) sanitizers; tabel-namen uit hardcoded array
--   - Batch atomicity all-or-nothing (partial state = inconsistent snapshot)
--
-- Manuele trigger:
--   docker exec supabase_db_basejump-next psql -U postgres -c \
--     "select public.create_parameter_snapshot('ad-hoc');"
--
-- Import scripts (T-018+) roepen via server-side supabase client met service key.


-- ================================================================
-- 1) TABLE audit_parameter_snapshot
-- ================================================================

create table public.audit_parameter_snapshot (
    snapshot_id uuid primary key default gen_random_uuid(),
    snapshot_batch_id uuid not null,
    taken_at timestamptz not null default now(),
    reden text not null,
    tabel_naam text not null,
    rowcount int not null,
    active_rowcount int not null,
    distinct_bron_url_count int not null,
    has_null_bron_url boolean not null,
    open_ended_count int not null,
    max_geldig_van date null,
    min_geldig_van date null,
    checksum text not null,
    created_at timestamptz not null default now(),
    unique (snapshot_batch_id, tabel_naam)
);

comment on table public.audit_parameter_snapshot is
    'Per-tabel snapshot rijen. Elke create_parameter_snapshot() invocation levert 11 rijen (één per param_* tabel) met dezelfde snapshot_batch_id. Append-only log per Constitution v1.0.1 regels 291-293 parameter-snapshot audit.';

comment on column public.audit_parameter_snapshot.snapshot_batch_id is
    'Groepeert 11 rijen per invocation. Nieuwe uuid per create_parameter_snapshot() call — laat cross-batch checksum-diff toe (idempotency-detectie).';

comment on column public.audit_parameter_snapshot.has_null_bron_url is
    'Invariant: MUST be false. Constitution regel 234 vereist bron_url op elke parameterrij.';

comment on column public.audit_parameter_snapshot.checksum is
    'md5 van geconcatenteerde rijen ordered by geldig_van + bron_url. Includes created_at/updated_at timestamps — cross-environment vergelijking vereist deterministic hash (out-of-scope POC).';

create index audit_parameter_snapshot_batch_idx
    on public.audit_parameter_snapshot (snapshot_batch_id, tabel_naam);

alter table public.audit_parameter_snapshot enable row level security;

create policy audit_parameter_snapshot_read_all on public.audit_parameter_snapshot
    for select to authenticated using (true);

revoke insert, update, delete on public.audit_parameter_snapshot from authenticated, public, anon;


-- ================================================================
-- 2) FUNCTION create_parameter_snapshot(reden)
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
        'param_wagen_mobiliteit','param_index'
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

comment on function public.create_parameter_snapshot(text) is
    'Creëert een parameter-snapshot batch: 11 rijen in audit_parameter_snapshot (één per param_* tabel). Returns snapshot_batch_id. SECURITY DEFINER met pinned search_path voorkomt privilege escalation. Batch is atomic (all-or-nothing) — partial state = inconsistent snapshot.';

-- GRANT EXECUTE alleen aan service_role (voorkomt authenticated spam-inserts).
-- Manuele trigger via psql als postgres owner blijft werken.
revoke execute on function public.create_parameter_snapshot(text) from public, authenticated, anon;
grant execute on function public.create_parameter_snapshot(text) to service_role;
