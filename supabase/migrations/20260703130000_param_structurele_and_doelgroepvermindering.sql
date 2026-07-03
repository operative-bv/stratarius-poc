-- ================================================================
-- T-016: param_structurele_vermindering + param_doelgroepvermindering
-- ================================================================
-- Tweede parameter-laag migration in Phase 4, na T-015. Beide tabellen:
--   - Effective-dated met btree_gist exclusion (Principe I DB-niveau enforcement,
--     btree_gist extension al toegevoegd door T-015).
--   - Global reference (idem RLS pattern: to authenticated + REVOKE writes).
--   - Voeden de rekencascade als pro rata mu-verminderingen (Principe IV).
--
-- Belgische context (PDF Laag 3):
--   - Structurele vermindering: RSZ-verlaging per werkgeverscategorie (1|2|3).
--     Formule R = F - a*(S0-S) - b*(S1-S), waar F=forfait, a/b coefficient
--     parameters, S=referentie-loon. Per werkgeverscategorie eigen triplet.
--   - Doelgroepvermindering: gewest-specifieke verminderingen (6e
--     Staatshervorming heeft Vlaams / Waals / Brussels beleid uit elkaar
--     getrokken). Per (gewest, doelgroep, periode) eigen forfait + coefficient
--     + voorwaarden_json (leeftijd, werkloosheidsduur, opleiding, etc).
--
-- Geen seed data in dit migration bestand: concrete tarieven en gewest-specifieke
-- doelgroepen komen via T-018+. Do NOT add ad-hoc test rows here.
--
-- Bron: PDF Laag 3 parameter-tabellen + RSZ instructiegids + VDAB/Forem/Actiris.
-- https://www.socialsecurity.be/employer/instructions/


-- ================================================================
-- 1) TABLE param_structurele_vermindering
-- ================================================================

create table public.param_structurele_vermindering (
    param_structurele_id uuid primary key default gen_random_uuid(),
    werkgeverscategorie smallint not null check (werkgeverscategorie in (1, 2, 3)),
    geldig_van date not null,
    geldig_tot date null,
    forfait numeric(18, 4) not null,
    coefficient_a numeric(12, 8) not null,
    coefficient_b numeric(12, 8) not null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        werkgeverscategorie with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_structurele_vermindering is
    'Effective-dated structurele RSZ-vermindering per werkgeverscategorie. Formule R = F - a*(S0-S) - b*(S1-S). Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_structurele_vermindering.param_structurele_id is
    'UUID surrogate PK: composite (werkgeverscategorie, geldig_van) is uniek maar onhandig door te geven in de rekencascade.';
comment on column public.param_structurele_vermindering.werkgeverscategorie is
    'Data-driven key (Principe II) matcht dim_legale_entiteit.werkgeverscategorie en param_rsz.werkgeverscategorie: 1=algemeen/prive, 2=social profit, 3=beschutte werkplaats.';
comment on column public.param_structurele_vermindering.forfait is
    'Forfait F in EUR (numeric(18,4) per Constitution v1.0.1 money precision).';
comment on column public.param_structurele_vermindering.coefficient_a is
    'Coefficient a in formule R = F - a*(S0-S) - b*(S1-S). numeric(12,8) per Constitution v1.0.1 dimensieloze coefficient precisie (expliciet in de precision-tabel genoemd).';
comment on column public.param_structurele_vermindering.coefficient_b is
    'Coefficient b in formule R = F - a*(S0-S) - b*(S1-S). numeric(12,8) idem coefficient_a.';

alter table public.param_structurele_vermindering enable row level security;

create policy param_structurele_vermindering_read_all on public.param_structurele_vermindering
    for select to authenticated using (true);

revoke insert, update, delete on public.param_structurele_vermindering from authenticated, public, anon;

create trigger param_structurele_vermindering_set_timestamps
    before insert or update on public.param_structurele_vermindering
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 2) TABLE param_doelgroepvermindering
-- ================================================================

create table public.param_doelgroepvermindering (
    param_doelgroep_id uuid primary key default gen_random_uuid(),
    gewest text not null check (gewest in ('vlaanderen', 'wallonie', 'brussel')),
    doelgroep text not null,
    geldig_van date not null,
    geldig_tot date null,
    forfait numeric(18, 4) not null,
    coefficient numeric(12, 8) not null,
    voorwaarden_json jsonb not null default '{}'::jsonb,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        gewest with =,
        doelgroep with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_doelgroepvermindering is
    'Effective-dated gewest-specifieke RSZ-doelgroepvermindering. Sinds 6e Staatshervorming eigen beleid per gewest. Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_doelgroepvermindering.param_doelgroep_id is
    'UUID surrogate PK: composite (gewest, doelgroep, geldig_van) is uniek maar onhandig door te geven.';
comment on column public.param_doelgroepvermindering.gewest is
    'Belgische regio: vlaanderen (VDAB), wallonie (Forem), brussel (Actiris). CHECK constraint ipv native enum voor consistency met andere text CHECK-columns (bv param_rsz.status).';
comment on column public.param_doelgroepvermindering.doelgroep is
    'Semantic identifier (bv langdurig_werkloos, jongere_zonder_diploma, oudere, gehandicapt, eerste_aanwerving). Text ipv FK omdat catalogus evolueert bij nieuwe wetgeving.';
comment on column public.param_doelgroepvermindering.forfait is
    'Forfait in EUR (numeric(18,4) per Constitution v1.0.1 money precision).';
comment on column public.param_doelgroepvermindering.coefficient is
    'Vermindering-coefficient. numeric(12,8) per Constitution v1.0.1 dimensieloze coefficient precisie.';
comment on column public.param_doelgroepvermindering.voorwaarden_json is
    'Flexibele voorwaarden-schema voor doelgroep-classificatie (bv {"min_leeftijd":50}, {"werkloos_min_maanden":12,"kwalificatie":"laaggeschoold"}). NOT NULL met DEFAULT ''{}''::jsonb: import-scripts kunnen omitten wanneer een doelgroep geen filter-criteria heeft.';

alter table public.param_doelgroepvermindering enable row level security;

create policy param_doelgroepvermindering_read_all on public.param_doelgroepvermindering
    for select to authenticated using (true);

revoke insert, update, delete on public.param_doelgroepvermindering from authenticated, public, anon;

create trigger param_doelgroepvermindering_set_timestamps
    before insert or update on public.param_doelgroepvermindering
    for each row execute function basejump.trigger_set_timestamps();
