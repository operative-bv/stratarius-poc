-- ================================================================
-- T-049: param_arbeidsongevallen tabel + cascade_stap9_arbeidsongevallen functie
-- ================================================================
--
-- Nieuwe parameter-tabel + cascade functie in één migration (kleine table,
-- volgt sibling patroon voor eenvoudige extension).
--
-- Constitution Principe I (Effective-Dating Everywhere): btree_gist exclusion
-- constraint voorkomt overlap op DB-niveau per (pc_id, daterange).
--
-- Principe II data-driven: tarief_pct en min_premie uit param_arbeidsongevallen
-- via (pc_id, periode) temporele join. GEEN hardcoded 0.30% of 0.60% in
-- function-body.
--
-- Principe III: pure SQL functie STABLE PARALLEL SAFE met pinned search_path.
--
-- Principe V TDD 2-commit: test-commit 52- staat vóór deze migration.
--
-- Formule:
--   maandbedrag = max(min_premie / 12, rsz_grondslag × tarief_pct)
--   (min_premie is jaarlijkse floor, /12 voor maandelijkse cascade-output)
--
-- NULL contract (consistent met T-041, T-042, T-048):
--   Temporele join miss (onbekende pc_id of periode) → NULL.
--   Cascade orchestrator T-029 detecteert NULL en throwt gestructureerde fout.
--
-- Ook: uitbreiding create_parameter_snapshot() v_tables array met de nieuwe tabel
-- (Constitution regel 291-293: parameter-snapshot audit per param_* tabel).
--
-- Rollback:
--   DROP FUNCTION public.cascade_stap9_arbeidsongevallen(numeric, text, date);
--   DROP TABLE public.param_arbeidsongevallen;
--   -- + create_parameter_snapshot v_tables reverten naar 11 tabellen


-- ================================================================
-- 1) TABLE param_arbeidsongevallen
-- ================================================================

create table public.param_arbeidsongevallen (
    param_arbeidsongevallen_id uuid primary key default gen_random_uuid(),
    pc_id text not null references public.dim_pc (pc_id) on delete restrict,
    geldig_van date not null,
    geldig_tot date null,
    tarief_pct numeric(6, 4) not null,
    min_premie numeric(18, 4) not null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        pc_id with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_arbeidsongevallen is
    'Effective-dated arbeidsongevallenverzekering tarief per PC. Global reference (niet tenant-scoped — wettelijke tarieven per sector/risicoklasse). Principe I: exclusion constraint voorkomt overlap op DB-niveau. Productie-uitbreiding: sector-differentiatie binnen PC (aparte ticket).';
comment on column public.param_arbeidsongevallen.pc_id is
    'FK naar dim_pc (text-PK per T-007 schema). ON DELETE RESTRICT: parameter-rijen mogen niet stilzwijgend verdwijnen; dim_pc gebruikt status=deprecated ipv delete.';
comment on column public.param_arbeidsongevallen.tarief_pct is
    'Arbeidsongevallen-verzekeringstarief als rate (bv 0.0030 = 0.30%). numeric(6,4) per Constitution v1.0.1 non-money precision.';
comment on column public.param_arbeidsongevallen.min_premie is
    'Jaarlijkse minimum-premie in EUR. Cascade functie converteert naar maand via /12 voor consistente output. numeric(18,4) per Constitution v1.0.1 money precision.';

alter table public.param_arbeidsongevallen enable row level security;

create policy param_arbeidsongevallen_read_all on public.param_arbeidsongevallen
    for select to authenticated using (true);

revoke insert, update, delete on public.param_arbeidsongevallen from authenticated, public, anon;

create trigger param_arbeidsongevallen_set_timestamps
    before insert or update on public.param_arbeidsongevallen
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 2) Seed 2024 baseline (POC_UNVERIFIED — cross-check per productie-deploy)
-- ================================================================

insert into public.param_arbeidsongevallen (pc_id, geldig_van, geldig_tot, tarief_pct, min_premie, bron_url, bron_document)
select v.pc_id, v.geldig_van, v.geldig_tot, v.tarief_pct, v.min_premie, v.bron_url, v.bron_document
from (values
    ('200'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0030::numeric(6,4), 60.0000::numeric(18,4),
     'https://www.fedris.be/nl/professional/werkgevers/verzekering'::text,
     '[POC_UNVERIFIED_2024] Fedris — PC 200 aanvullend bedienden geschat op 0.30% (laag risico kantoor); min_premie 60 EUR/jaar. Productie moet echte tarieven van verzekeringsmaatschappij per risicoklasse gebruiken.'::text),
    ('302'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0060::numeric(6,4), 60.0000::numeric(18,4),
     'https://www.fedris.be/nl/professional/werkgevers/verzekering'::text,
     '[POC_UNVERIFIED_2024] Fedris — PC 302 horeca geschat op 0.60% (hoger risico); min_premie 60 EUR/jaar.'::text)
) as v(pc_id, geldig_van, geldig_tot, tarief_pct, min_premie, bron_url, bron_document)
where not exists (
    select 1 from public.param_arbeidsongevallen t
    where t.pc_id = v.pc_id
      and t.geldig_van = v.geldig_van
);


-- ================================================================
-- 3) FUNCTION cascade_stap9_arbeidsongevallen
-- ================================================================

create or replace function public.cascade_stap9_arbeidsongevallen(
    p_rsz_grondslag numeric(18, 4),
    p_pc_id         text,
    p_periode       date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    with param as (
        select pa.tarief_pct, pa.min_premie
        from public.param_arbeidsongevallen pa
        where pa.pc_id = p_pc_id
          and p_periode >= pa.geldig_van
          and (pa.geldig_tot is null or p_periode < pa.geldig_tot)
        limit 1
    )
    select greatest(
        (p.min_premie / 12)::numeric(18, 4),
        (p_rsz_grondslag * p.tarief_pct)::numeric(18, 4)
    )::numeric(18, 4)
    from param p;
$$;

comment on function public.cascade_stap9_arbeidsongevallen(numeric, text, date) is
    'Cascade stap 9: arbeidsongevallenverzekering = max(min_premie/12, rsz_grondslag × tarief_pct) via temporele join op param_arbeidsongevallen (pc_id, periode). Principe II data-driven. Principe I half-open interval [geldig_van, geldig_tot). NULL contract: temporele miss (onbekende pc_id/periode) -> NULL; cascade orchestrator T-029 detecteert. LANGUAGE SQL STABLE PARALLEL SAFE met pinned search_path.';

grant execute on function public.cascade_stap9_arbeidsongevallen(numeric, text, date) to authenticated;


-- ================================================================
-- 4) Uitbreiding create_parameter_snapshot (12 tabellen)
-- ================================================================
-- Constitution regel 291-293 vereist snapshot per parameter-tabel.
-- Voeg param_arbeidsongevallen toe aan de enumeration.

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
        'param_wagen_mobiliteit','param_index','param_arbeidsongevallen'
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
    'Creëert een parameter-snapshot batch: 12 rijen in audit_parameter_snapshot (één per param_* tabel, inclusief param_arbeidsongevallen sinds T-049). Returns snapshot_batch_id. SECURITY DEFINER met pinned search_path voorkomt privilege escalation. Batch is atomic (all-or-nothing).';
