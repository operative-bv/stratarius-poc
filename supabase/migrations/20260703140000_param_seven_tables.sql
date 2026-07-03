-- ================================================================
-- T-017: 7 param_* tabellen effective-dated (Phase 4 afronding parameterlaag)
-- ================================================================
-- Derde en laatste parameter-laag schema-migration in Phase 4, na T-015 en T-016.
-- Voegt de resterende 7 tabellen toe die de parameterlaag afronden:
--   1) param_arbeidsduur           — pc-specifieke gemiddelde wekelijkse uren (S-referentie mu = Q/S)
--   2) param_vakantiegeld          — enkel/dubbel percentage per statuut (arbeider|bediende)
--   3) param_index                 — pc-specifieke indexcoefficient + centenindex-drempel
--   4) param_bijzondere_bijdragen  — fso/bev/asbest/loonmatiging tarief + formule
--   5) param_sectorbijdrage        — pc + fonds tarief (bestaanszekerheid, vorming, etc.)
--   6) param_extralegaal           — voordeeltype max_wg + taks_pct (maaltijdcheques, groepsverz.)
--   7) param_wagen_mobiliteit      — CO2-solidariteit + VAA + mobiliteitsbudget parameters
--
-- Alle tabellen volgen het pattern gevestigd door T-015 en T-016:
--   - Effective-dated met btree_gist exclusion (Principe I DB-niveau enforcement).
--   - Global reference: RLS `to authenticated using (true)` + REVOKE writes.
--   - `bron_url NOT NULL` per PDF Laag 3 conventie.
--   - BE-only per POC-scope (idem ISS-031 — geen land_id kolom).
--
-- Geen seed data in dit migration bestand: concrete tarieven en fonds/voordeeltype
-- catalogus komen via T-018+. Do NOT add ad-hoc test rows here.
--
-- Geen `create extension if not exists btree_gist` — al aanwezig sinds T-015.
--
-- Bron: PDF Laag 3 parameter-tabellen + RSZ instructiegids + FOD Financien VAA.
-- https://www.socialsecurity.be/employer/instructions/


-- ================================================================
-- 1) TABLE param_arbeidsduur
-- ================================================================

create table public.param_arbeidsduur (
    param_arbeidsduur_id uuid primary key default gen_random_uuid(),
    pc_id text not null references public.dim_pc (pc_id) on delete restrict,
    geldig_van date not null,
    geldig_tot date null,
    gemiddelde_wekelijkse_uren numeric(6, 4) not null,
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

comment on table public.param_arbeidsduur is
    'Effective-dated gemiddelde wekelijkse arbeidsduur per PC. Voedt S-referentie in mu = Q/S rekencascade (Principe IV pro rata). Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_arbeidsduur.param_arbeidsduur_id is
    'UUID surrogate PK: composite (pc_id, geldig_van) is uniek maar onhandig door te geven in de rekencascade.';
comment on column public.param_arbeidsduur.pc_id is
    'FK naar dim_pc (text-PK per T-007 schema). ON DELETE RESTRICT: parameter-rijen mogen niet stilzwijgend verdwijnen; dim_pc gebruikt status=deprecated ipv delete.';
comment on column public.param_arbeidsduur.gemiddelde_wekelijkse_uren is
    'Gemiddelde wekelijkse uren (bv 38.0000 voor voltijds standaard). numeric(6,4) per Constitution v1.0.1 non-money precision (breuk/rate).';

alter table public.param_arbeidsduur enable row level security;

create policy param_arbeidsduur_read_all on public.param_arbeidsduur
    for select to authenticated using (true);

revoke insert, update, delete on public.param_arbeidsduur from authenticated, public, anon;

create trigger param_arbeidsduur_set_timestamps
    before insert or update on public.param_arbeidsduur
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 2) TABLE param_vakantiegeld
-- ================================================================

create table public.param_vakantiegeld (
    param_vakantiegeld_id uuid primary key default gen_random_uuid(),
    regime text not null check (regime in ('arbeider', 'bediende')),
    geldig_van date not null,
    geldig_tot date null,
    enkel_pct numeric(6, 4) not null,
    dubbel_pct numeric(6, 4) not null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        regime with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_vakantiegeld is
    'Effective-dated vakantiegeld percentages (enkel + dubbel) per statuut. Global reference. Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_vakantiegeld.param_vakantiegeld_id is
    'UUID surrogate PK: composite (regime, geldig_van) is uniek maar onhandig door te geven.';
comment on column public.param_vakantiegeld.regime is
    'Belgisch statuut: arbeider | bediende. Gesloten enum (fixed sinds ontstaan; wetgeving evolueert richting harmonisatie maar tabel-domein blijft dit tweetal).';
comment on column public.param_vakantiegeld.enkel_pct is
    'Enkelvoudig vakantiegeld als rate (bv 0.0692 voor bedienden ~6.92% van bruto). numeric(6,4) per Constitution v1.0.1 non-money precision.';
comment on column public.param_vakantiegeld.dubbel_pct is
    'Dubbel vakantiegeld als rate (bv 0.0920 = 92% van maandloon). numeric(6,4) per Constitution v1.0.1 non-money precision.';

alter table public.param_vakantiegeld enable row level security;

create policy param_vakantiegeld_read_all on public.param_vakantiegeld
    for select to authenticated using (true);

revoke insert, update, delete on public.param_vakantiegeld from authenticated, public, anon;

create trigger param_vakantiegeld_set_timestamps
    before insert or update on public.param_vakantiegeld
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 3) TABLE param_index
-- ================================================================

create table public.param_index (
    param_index_id uuid primary key default gen_random_uuid(),
    pc_id text not null references public.dim_pc (pc_id) on delete restrict,
    geldig_van date not null,
    geldig_tot date null,
    index_coefficient numeric(10, 6) not null,
    drempel_bruto numeric(18, 4) not null,
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

comment on table public.param_index is
    'Effective-dated indexcoefficient + centenindex-drempel per PC. Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_index.param_index_id is
    'UUID surrogate PK: composite (pc_id, geldig_van) is uniek maar onhandig door te geven.';
comment on column public.param_index.pc_id is
    'FK naar dim_pc (text-PK per T-007 schema). ON DELETE RESTRICT: parameter-rijen mogen niet stilzwijgend verdwijnen; dim_pc gebruikt status=deprecated ipv delete.';
comment on column public.param_index.index_coefficient is
    'Indexcoefficient (bv 1.020000 voor 2% index). numeric(10,6) EXPLICIET genoemd in Constitution v1.0.1 precision-tabel voor deze kolom (praktisch bereik 0.95-1.15).';
comment on column public.param_index.drempel_bruto is
    'Centenindex-drempel bruto (bv €4.000 cap voor gedeeltelijke indexering). numeric(18,4) per Constitution v1.0.1 money precision.';

alter table public.param_index enable row level security;

create policy param_index_read_all on public.param_index
    for select to authenticated using (true);

revoke insert, update, delete on public.param_index from authenticated, public, anon;

create trigger param_index_set_timestamps
    before insert or update on public.param_index
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 4) TABLE param_bijzondere_bijdragen
-- ================================================================

create table public.param_bijzondere_bijdragen (
    param_bijzondere_bijdragen_id uuid primary key default gen_random_uuid(),
    type text not null check (type in ('fso', 'bev', 'asbest', 'loonmatiging')),
    geldig_van date not null,
    geldig_tot date null,
    tarief numeric(6, 4) not null,
    formule_json jsonb not null default '{}'::jsonb,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        type with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_bijzondere_bijdragen is
    'Effective-dated bijzondere RSZ-bijdragen (FSO, BEV, asbestfonds, loonmatiging). Global reference. Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_bijzondere_bijdragen.param_bijzondere_bijdragen_id is
    'UUID surrogate PK: composite (type, geldig_van) is uniek maar onhandig door te geven.';
comment on column public.param_bijzondere_bijdragen.type is
    'Gesloten enum per PDF Laag 3: fso (fonds sluiting ondernemingen) | bev (bijzondere bijdrage werkloosheid) | asbest (asbestfonds) | loonmatiging (loonmatigingsbijdrage).';
comment on column public.param_bijzondere_bijdragen.tarief is
    'Bijdrage-tarief als rate (bv 0.0056 voor FSO). numeric(6,4) per Constitution v1.0.1 non-money precision.';
comment on column public.param_bijzondere_bijdragen.formule_json is
    'Flexibele formule-config (bv {"formule":"0.5 * indexbesparing"} voor loonmatiging; {"basis":"brutoloon_wettelijk"} voor asbest). NOT NULL met DEFAULT ''{}''::jsonb: import-scripts kunnen omitten voor eenvoudige tarief-only rijen. Precedent voorwaarden_json T-016.';

alter table public.param_bijzondere_bijdragen enable row level security;

create policy param_bijzondere_bijdragen_read_all on public.param_bijzondere_bijdragen
    for select to authenticated using (true);

revoke insert, update, delete on public.param_bijzondere_bijdragen from authenticated, public, anon;

create trigger param_bijzondere_bijdragen_set_timestamps
    before insert or update on public.param_bijzondere_bijdragen
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 5) TABLE param_sectorbijdrage
-- ================================================================

create table public.param_sectorbijdrage (
    param_sectorbijdrage_id uuid primary key default gen_random_uuid(),
    pc_id text not null references public.dim_pc (pc_id) on delete restrict,
    fonds text not null check (fonds ~ '^[a-z0-9_]+$'),
    geldig_van date not null,
    geldig_tot date null,
    tarief numeric(6, 4) not null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        pc_id with =,
        fonds with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_sectorbijdrage is
    'Effective-dated sector-bijdragen per PC per fonds (bestaanszekerheid, vorming, risicogroepen, ejp, etc.). Open catalogus omdat fondsen wisselen per CAO. Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_sectorbijdrage.param_sectorbijdrage_id is
    'UUID surrogate PK: composite (pc_id, fonds, geldig_van) is uniek maar onhandig door te geven.';
comment on column public.param_sectorbijdrage.pc_id is
    'FK naar dim_pc (text-PK per T-007 schema). ON DELETE RESTRICT: parameter-rijen mogen niet stilzwijgend verdwijnen; dim_pc gebruikt status=deprecated ipv delete.';
comment on column public.param_sectorbijdrage.fonds is
    'Fonds-identifier free-form (open catalogus: evolueert per CAO/PC). Regex ~ ''^[a-z0-9_]+$'' als defence-in-depth tegen typos, spaties en hoofdletter-varianten die phantom-splits kunnen creeren in de exclusion index. Precedent regex idem param_plafond_id (T-015).';
comment on column public.param_sectorbijdrage.tarief is
    'Sectorbijdrage-tarief als rate (bv 0.0100 = 1.00%). numeric(6,4) per Constitution v1.0.1 non-money precision.';

alter table public.param_sectorbijdrage enable row level security;

create policy param_sectorbijdrage_read_all on public.param_sectorbijdrage
    for select to authenticated using (true);

revoke insert, update, delete on public.param_sectorbijdrage from authenticated, public, anon;

create trigger param_sectorbijdrage_set_timestamps
    before insert or update on public.param_sectorbijdrage
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 6) TABLE param_extralegaal
-- ================================================================

create table public.param_extralegaal (
    param_extralegaal_id uuid primary key default gen_random_uuid(),
    voordeeltype text not null check (voordeeltype ~ '^[a-z0-9_]+$'),
    geldig_van date not null,
    geldig_tot date null,
    max_wg numeric(18, 4) not null,
    taks_pct numeric(6, 4) not null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        voordeeltype with =,
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_extralegaal is
    'Effective-dated extralegale voordelen (maaltijdcheques, groepsverzekering, mobiliteitsbudget, etc.). Open catalogus omdat nieuwe voordelen ontstaan bij wetgeving. Principe I: exclusion constraint voorkomt overlap op DB-niveau.';
comment on column public.param_extralegaal.param_extralegaal_id is
    'UUID surrogate PK: composite (voordeeltype, geldig_van) is uniek maar onhandig door te geven.';
comment on column public.param_extralegaal.voordeeltype is
    'Voordeel-identifier free-form (open catalogus: nieuwe voordelen komen erbij per wetgeving). Extralegaal is globaal-scoped (niet per-PC zoals sectorbijdrage) dus 1 typo pollueert het hele land. Regex ~ ''^[a-z0-9_]+$'' als defence-in-depth tegen typos/spaties/hoofdletter-varianten. Precedent regex idem param_plafond_id (T-015).';
comment on column public.param_extralegaal.max_wg is
    'Maximum werkgevers-tussenkomst in EUR (bv €7.00 per maaltijdcheque). numeric(18,4) per Constitution v1.0.1 money precision.';
comment on column public.param_extralegaal.taks_pct is
    'Taks-percentage als rate (bv 0.0886 = 8.86% groepsverzekering-taks). numeric(6,4) per Constitution v1.0.1 non-money precision.';

alter table public.param_extralegaal enable row level security;

create policy param_extralegaal_read_all on public.param_extralegaal
    for select to authenticated using (true);

revoke insert, update, delete on public.param_extralegaal from authenticated, public, anon;

create trigger param_extralegaal_set_timestamps
    before insert or update on public.param_extralegaal
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 7) TABLE param_wagen_mobiliteit
-- ================================================================

create table public.param_wagen_mobiliteit (
    param_wagen_mobiliteit_id uuid primary key default gen_random_uuid(),
    geldig_van date not null,
    geldig_tot date null,
    co2_formule_json jsonb not null default '{}'::jsonb,
    referentie_co2 smallint not null check (referentie_co2 between 50 and 400),
    minimumbijdrage numeric(18, 4) not null,
    vaa_coefficient numeric(12, 8) not null,
    bron_url text not null,
    bron_document text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (geldig_tot is null or geldig_van < geldig_tot),
    exclude using gist (
        daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
    )
);

comment on table public.param_wagen_mobiliteit is
    'Effective-dated wagen-mobiliteit parameters (CO2-solidariteitsbijdrage, VAA-coefficient, minimumbijdrage). Global reference (niet gediscrimineerd op andere key). Principe I: single-key exclusion op daterange voorkomt overlap op DB-niveau.';
comment on column public.param_wagen_mobiliteit.param_wagen_mobiliteit_id is
    'UUID surrogate PK: composite (geldig_van) alleen is uniek maar UUID is consistent met andere param_* tabellen.';
comment on column public.param_wagen_mobiliteit.co2_formule_json is
    'CO2-solidariteitsbijdrage formule-config (bv {"formule":"((co2 - referentie) * factor + basis) / 12", "factor":9.0}). NOT NULL met DEFAULT ''{}''::jsonb: import-scripts kunnen omitten wanneer formule impliciet in code zit. Precedent voorwaarden_json T-016.';
comment on column public.param_wagen_mobiliteit.referentie_co2 is
    'discrete g/km CO2-emissie; range 50-400 is sanity guard voor typos, business-range typisch 90-200. smallint gerechtvaardigd omdat Constitution integer-verbod voor centen/geldbedragen geldt, niet voor engineering-eenheden.';
comment on column public.param_wagen_mobiliteit.minimumbijdrage is
    'Minimumbijdrage per maand in EUR. numeric(18,4) per Constitution v1.0.1 money precision.';
comment on column public.param_wagen_mobiliteit.vaa_coefficient is
    'Dimensieloze multiplier (bv brandstoftype-factor 1.0500 = 5% opslag). NIET een rate/percentage — als PDF Laag 3 bij T-018 als rate blijkt, migratie naar numeric(6,4).';

alter table public.param_wagen_mobiliteit enable row level security;

create policy param_wagen_mobiliteit_read_all on public.param_wagen_mobiliteit
    for select to authenticated using (true);

revoke insert, update, delete on public.param_wagen_mobiliteit from authenticated, public, anon;

create trigger param_wagen_mobiliteit_set_timestamps
    before insert or update on public.param_wagen_mobiliteit
    for each row execute function basejump.trigger_set_timestamps();
