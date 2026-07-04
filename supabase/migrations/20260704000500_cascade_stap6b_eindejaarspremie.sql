-- ================================================================
-- T-047: param_eindejaarspremie tabel + cascade_stap6b_eindejaarspremie functie
-- ================================================================
--
-- Belgische eindejaarspremie ("13e maand"). Per PC/CAO varieert de berekening:
--   PC 200 (bedienden): typisch 1 maandloon per jaar
--   PC 302 (horeca): 1 maandloon per jaar per CAO
--   PC 124 (bouw): eigen forfait via Fonds — POC deferred
--
-- POC-simplification: coefficient-based ipv gelijkstellingen-berekening uit
-- fact_prestatie. Formule = bruto × coefficient / 12 (jaarpremie verdeeld over
-- 12 maanden als accrual per maand).
--
-- Uitbreiding gelijkstellingen (uren × basisloon × PC-coefficient via
-- dim_prestatiecode.gelijkgesteld_eindejaarspremie tag) is productie-scope,
-- aparte follow-up ticket.
--
-- Constitution Principe I: btree_gist exclusion op (pc_id, daterange).
-- Constitution Principe II: coefficient uit param_eindejaarspremie via
--   temporele join, geen hardcoded 1.0 in function-body.
-- Constitution Principe III: pure SQL functie STABLE PARALLEL SAFE.
-- Constitution Principe V: test-first commit 56- vóór deze migration.
--
-- Naming: 'stap6b' omdat sibling van cascade_stap6_vakantiegeld (T-044).
-- Beide zijn "provisies" die de wg maandelijks moet reserveren voor jaarlijkse
-- uitbetaling. Alternatief 'stap6_eindejaarspremie' zou botsen; suffix b
-- houdt volgorde herkenbaar zonder heftige rename.
--
-- Ook: uitbreiding create_parameter_snapshot() v_tables array (nu 13 tabellen).
--
-- Rollback:
--   DROP FUNCTION public.cascade_stap6b_eindejaarspremie(numeric, text, date);
--   DROP TABLE public.param_eindejaarspremie;
--   -- + create_parameter_snapshot v_tables reverten naar 12 tabellen


-- ================================================================
-- 1) TABLE param_eindejaarspremie
-- ================================================================

create table public.param_eindejaarspremie (
    param_eindejaarspremie_id uuid primary key default gen_random_uuid(),
    pc_id text not null references public.dim_pc (pc_id) on delete restrict,
    geldig_van date not null,
    geldig_tot date null,
    coefficient numeric(6, 4) not null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    check (coefficient >= 0),
    exclude using gist (
        pc_id with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_eindejaarspremie is
    'Effective-dated eindejaarspremie coefficient per PC. Formule maandelijks: bruto × coefficient / 12. Coefficient 1.0 = 1 maandloon per jaar (standaard bedienden). Productie: gelijkstellingen via dim_prestatiecode tag ipv coefficient-only (aparte follow-up).';
comment on column public.param_eindejaarspremie.pc_id is
    'FK naar dim_pc (text-PK). ON DELETE RESTRICT: parameter-rijen mogen niet stilzwijgend verdwijnen.';
comment on column public.param_eindejaarspremie.coefficient is
    'Deel van jaarloon dat als eindejaarspremie geldt. numeric(6,4). 1.0000 = 1 maandloon per jaar; 0.8500 = 85% (voorbeeld bouw); 0.0000 = geen premie (uitgesloten sector).';


alter table public.param_eindejaarspremie enable row level security;

create policy param_eindejaarspremie_read_all on public.param_eindejaarspremie
    for select to authenticated using (true);

revoke insert, update, delete on public.param_eindejaarspremie from authenticated, public, anon;

grant select on public.param_eindejaarspremie to authenticated;

create trigger param_eindejaarspremie_set_timestamps
    before insert or update on public.param_eindejaarspremie
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 2) Seed 2024 baseline (POC_UNVERIFIED — cross-check per CAO)
-- ================================================================

insert into public.param_eindejaarspremie (pc_id, geldig_van, geldig_tot, coefficient, bron_url, bron_document)
select v.pc_id, v.geldig_van, v.geldig_tot, v.coefficient, v.bron_url, v.bron_document
from (values
    ('200'::text, '2024-01-01'::date, '2025-01-01'::date, 1.0000::numeric(6,4),
     'https://www.werk.belgie.be/nl/themas/verloning/eindejaarspremie'::text,
     '[POC_UNVERIFIED_2024] PC 200 aanvullend bedienden — CAO standaard eindejaarspremie 1 maandloon per jaar.'::text),
    ('302'::text, '2024-01-01'::date, '2025-01-01'::date, 1.0000::numeric(6,4),
     'https://www.horeca.be/nl/eindejaarspremie'::text,
     '[POC_UNVERIFIED_2024] PC 302 horeca — CAO standaard 1 maandloon eindejaarspremie per jaar.'::text)
) as v(pc_id, geldig_van, geldig_tot, coefficient, bron_url, bron_document)
where not exists (
    select 1 from public.param_eindejaarspremie t
    where t.pc_id = v.pc_id
      and t.geldig_van = v.geldig_van
);


-- ================================================================
-- 3) FUNCTION cascade_stap6b_eindejaarspremie
-- ================================================================

create or replace function public.cascade_stap6b_eindejaarspremie(
    p_bruto   numeric(18, 4),
    p_pc_id   text,
    p_periode date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    select ((p_bruto * pe.coefficient) / 12)::numeric(18, 4)
    from public.param_eindejaarspremie pe
    where pe.pc_id = p_pc_id
      and p_periode >= pe.geldig_van
      and (pe.geldig_tot is null or p_periode < pe.geldig_tot)
    limit 1;
$$;

comment on function public.cascade_stap6b_eindejaarspremie(numeric, text, date) is
    'Cascade stap 6b: eindejaarspremie provisie = (bruto × coefficient) / 12 via temporele join op param_eindejaarspremie (pc_id, periode). Principe II data-driven. Principe I half-open interval. NULL contract: temporele miss (onbekende pc_id/periode) -> NULL. LANGUAGE SQL STABLE PARALLEL SAFE met pinned search_path.';

grant execute on function public.cascade_stap6b_eindejaarspremie(numeric, text, date) to authenticated;


-- ================================================================
-- 4) Uitbreiding create_parameter_snapshot (13 tabellen)
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

comment on function public.create_parameter_snapshot(text) is
    'Creëert een parameter-snapshot batch: 13 rijen in audit_parameter_snapshot (één per param_* tabel, inclusief param_eindejaarspremie sinds T-047). Returns snapshot_batch_id.';
