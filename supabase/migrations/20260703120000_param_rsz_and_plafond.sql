-- ================================================================
-- T-015: param_rsz + param_plafond — effective-dated parameter layer
-- ================================================================
-- Eerste tickets van de Parameterlaag (Constitution Principe III's kern).
-- Deze migration:
--   1) Voegt btree_gist extension toe (voor exclusion constraints)
--   2) Maakt param_plafond (jaar/kwartaal plafonds, tekst-PK matcht T-010 forward-ref)
--   3) Maakt param_rsz (basisbijdrage_pct + arbeider-factor, uuid-PK)
--   4) ALTER TABLE dim_sz_behandeling ADD CONSTRAINT dim_sz_behandeling_cap_fk (T-010 forward-ref voldoen)
--
-- Constitution Principe I (Effective-Dating Everywhere) wordt hier op DATABASE-niveau
-- afgedwongen via btree_gist exclusion constraints — geen convention-based restrictie
-- meer, maar structurele onmogelijkheid van overlappende tijdvakken.
--
-- Geen seed data in dit migration bestand: concrete RSZ tarieven en plafond-waarden
-- worden ge-import via T-018+. Do NOT add ad-hoc test rows here.
--
-- Bron: PDF Laag 3 parameter-tabellen + RSZ instructiegids.
-- https://www.socialsecurity.be/employer/instructions/


-- ================================================================
-- 1) EXTENSION btree_gist
-- ================================================================
-- Nodig voor `WITH =` gecombineerd met `WITH &&` in exclusion constraints.
-- btree_gist is standard Postgres contrib en beschikbaar in Supabase managed.

create extension if not exists btree_gist;


-- ================================================================
-- 2) TABLE param_plafond
-- ================================================================

create table public.param_plafond (
    param_plafond_id text primary key check (param_plafond_id ~ '^[a-z0-9_]+$'),
    land_id text not null references public.dim_land (land_id) on delete restrict,
    bijdragetype text not null,
    geldig_van date not null,
    geldig_tot date null,
    jaarplafond numeric(18, 4) not null,
    kwartaalplafond numeric(18, 4) null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        land_id with =,
        bijdragetype with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_plafond is
    'Effective-dated jaar/kwartaal plafonds per land + bijdragetype (CAO 90, VIN wagen, etc.). Global reference. Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_plafond.param_plafond_id is
    'Semantische identifier (bv cao90_jaar_2024). Text-PK gekozen om te matchen met dim_sz_behandeling.cap_param_plafond_id (T-010 forward-ref). Regex CHECK afdwingt lowercase snake_case tegen malformed imports.';
comment on column public.param_plafond.jaarplafond is
    'Jaarplafond in EUR (numeric(18,4) per Constitution v1.0.1 money precision).';
comment on column public.param_plafond.kwartaalplafond is
    'Optioneel kwartaal-plafond wanneer regelgeving per kwartaal splitst.';
comment on column public.param_plafond.bijdragetype is
    'Groepering (bv cao90, vin_wagen, extralegaal_cheque). Deel van exclusion key: (land_id, bijdragetype, daterange).';

alter table public.param_plafond enable row level security;

-- S1: role-scoped SELECT policy (niet puur GRANT-vertrouwen).
create policy param_plafond_read_all on public.param_plafond
    for select to authenticated using (true);

revoke insert, update, delete on public.param_plafond from authenticated, public, anon;

create trigger param_plafond_set_timestamps
    before insert or update on public.param_plafond
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 3) TABLE param_rsz
-- ================================================================

create table public.param_rsz (
    param_rsz_id uuid primary key default gen_random_uuid(),
    status text not null check (status in ('arbeider', 'bediende')),
    werkgeverscategorie smallint not null check (werkgeverscategorie in (1, 2, 3)),
    geldig_van date not null,
    geldig_tot date null,
    basisbijdrage_pct numeric(6, 4) not null,
    basisfactor_pct numeric(6, 4) null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    check (
        (status = 'bediende' and basisfactor_pct is null)
        or (status = 'arbeider' and basisfactor_pct is not null)
    ),
    exclude using gist (
        status with =,
        werkgeverscategorie with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_rsz is
    'Effective-dated RSZ basisbijdrage per (status, werkgeverscategorie). Global reference. Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_rsz.param_rsz_id is
    'UUID surrogate PK: composite (status, werkgeverscategorie, geldig_van) is uniek maar onhandig om overal door te geven.';
comment on column public.param_rsz.basisbijdrage_pct is
    'RSZ-tarief als rate (bv 0.2540 = 25.40%). numeric(6,4) per Constitution v1.0.1 non-money precision.';
comment on column public.param_rsz.basisfactor_pct is
    'Multiplicatieve factor voor arbeider-grondslag (bv 1.08 = 108% loonverhoging voor vakantiegeld). NIET dezelfde semantiek als basisbijdrage_pct (rate vs factor). NULL voor bediende-rijen (biconditional CHECK).';

alter table public.param_rsz enable row level security;

create policy param_rsz_read_all on public.param_rsz
    for select to authenticated using (true);

revoke insert, update, delete on public.param_rsz from authenticated, public, anon;

create trigger param_rsz_set_timestamps
    before insert or update on public.param_rsz
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 4) ALTER TABLE dim_sz_behandeling — T-010 forward-ref voldoen
-- ================================================================
-- T-010 heeft cap_param_plafond_id text NULL aangemaakt in afwachting
-- van deze FK. Alle bestaande dim_sz_behandeling rijen hebben
-- cap_param_plafond_id = NULL (T-010 seed), dus ALTER is safe.

alter table public.dim_sz_behandeling
    add constraint dim_sz_behandeling_cap_fk
    foreign key (cap_param_plafond_id) references public.param_plafond (param_plafond_id) on delete restrict;
