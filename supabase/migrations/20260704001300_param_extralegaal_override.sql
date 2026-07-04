-- ================================================================
-- T-053: tenant-scoped param overrides — POC scope: extralegaal
-- ================================================================
--
-- Belgische wet: sommige extralegale voordeel-tarieven zijn CAO-specifiek en
-- kunnen per werkgever/sector afwijken van de globale defaults. POC POC
-- introduceert dit patroon voor param_extralegaal.
--
-- Design (optie A uit T-053 ticket-body):
--   Nieuwe tabel param_extralegaal_override per (owning_account_id, voordeeltype,
--   periode). btree_gist exclusion voorkomt overlap per (tenant, voordeeltype).
--   Cascade-lookup: eerst tenant-override, fallback naar globaal.
--
-- Waarom optie A (nieuwe tabel) en niet B (nullable owning_account_id op globaal):
--   - Schema-symmetrie: globale param_extralegaal blijft globaal (Principe II
--     data-driven zonder tenant-noise).
--   - Overrides expliciet zichtbaar en apart auditbaar.
--   - RLS-scoping simpel: override is tenant-scoped, globaal is read-all.
--   - Rollback: DROP override → gedrag zoals voor de migration.
--
-- Sibling param tabellen (sectorbijdrage, wagen_mobiliteit) volgen hetzelfde
-- patroon zodra tenant-behoefte ontstaat. Aparte tickets. RSZ + plafond blijven
-- expliciet globaal (wettelijk).
--
-- Ook: create_parameter_snapshot v_tables uitgebreid naar 14 tabellen inclusief
-- de nieuwe override-tabel.
--
-- Rollback:
--   DROP FUNCTION public.resolve_extralegaal_taks(uuid, text, date);
--   DROP TABLE public.param_extralegaal_override;


-- ================================================================
-- 1) TABLE param_extralegaal_override
-- ================================================================

create table public.param_extralegaal_override (
    param_extralegaal_override_id uuid primary key default gen_random_uuid(),
    owning_account_id uuid not null references basejump.accounts (id) on delete restrict,
    voordeeltype text not null check (voordeeltype ~ '^[a-z0-9_]+$'),
    geldig_van date not null,
    geldig_tot date null,
    max_wg numeric(18, 4) not null check (max_wg >= 0),
    taks_pct numeric(6, 4) not null check (taks_pct between 0 and 1),
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        owning_account_id with =,
        voordeeltype with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_extralegaal_override is
    'Tenant-scoped override voor param_extralegaal. Cascade-lookup preferereert tenant-override boven globale param_extralegaal. Principe I effective-dating met btree_gist exclusion per (tenant, voordeeltype). Precedent voor sibling overrides (sectorbijdrage, wagen_mobiliteit) — aparte tickets als gebruikt.';
comment on column public.param_extralegaal_override.owning_account_id is
    'FK naar basejump.accounts. Tenant-scoping. ON DELETE RESTRICT: overrides mogen niet stilzwijgend verdwijnen bij account-cleanup.';

alter table public.param_extralegaal_override enable row level security;

-- Tenant-scoped read via basejump role check
create policy param_extralegaal_override_tenant on public.param_extralegaal_override
    for select to authenticated
    using (basejump.has_role_on_account(owning_account_id));

-- Writes REVOKED — configuration change gaat via admin RPC of migration.
revoke insert, update, delete on public.param_extralegaal_override from authenticated, public, anon;

grant select on public.param_extralegaal_override to authenticated;

create index param_extralegaal_override_tenant_voordeel_idx
    on public.param_extralegaal_override (owning_account_id, voordeeltype);

create trigger param_extralegaal_override_set_timestamps
    before insert or update on public.param_extralegaal_override
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 2) FUNCTION resolve_extralegaal_taks
-- ================================================================

create or replace function public.resolve_extralegaal_taks(
    p_owning_account_id uuid,
    p_voordeeltype      text,
    p_periode           date
)
    returns numeric(6, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    -- COALESCE: eerst tenant-override, fallback naar globaal.
    select coalesce(
        (
            select ov.taks_pct
            from public.param_extralegaal_override ov
            where ov.owning_account_id = p_owning_account_id
              and ov.voordeeltype = p_voordeeltype
              and p_periode >= ov.geldig_van
              and (ov.geldig_tot is null or p_periode < ov.geldig_tot)
            limit 1
        ),
        (
            select pg.taks_pct
            from public.param_extralegaal pg
            where pg.voordeeltype = p_voordeeltype
              and p_periode >= pg.geldig_van
              and (pg.geldig_tot is null or p_periode < pg.geldig_tot)
            limit 1
        )
    )::numeric(6, 4);
$$;

comment on function public.resolve_extralegaal_taks(uuid, text, date) is
    'Resolve effective extralegaal taks_pct: eerst tenant-override (param_extralegaal_override), fallback naar globaal (param_extralegaal). Principe I temporele join. NULL wanneer geen match in beide tabellen. Gebruik door cascade functies en populatie_snapshot voor tenant-specific extralegaal-berekening.';

grant execute on function public.resolve_extralegaal_taks(uuid, text, date) to authenticated;


-- ================================================================
-- 3) Uitbreiding create_parameter_snapshot (14 tabellen)
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
        'param_eindejaarspremie','param_extralegaal_override'
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
    'Creëert een parameter-snapshot batch: 14 rijen in audit_parameter_snapshot (13 globale param_* tabellen + param_extralegaal_override sinds T-053). Returns snapshot_batch_id.';
