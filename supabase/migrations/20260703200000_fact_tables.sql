-- ================================================================
-- T-022: Fact tables voor rekencascade (Phase 5 start)
-- ================================================================
--
-- Legt de 3 input-fact-tabellen + 1 output-fact-tabel aan:
--   - fact_looncomponent (input, scenario-gebonden)
--   - fact_prestatie (input, scenario-vrij)
--   - fact_wagen (input, scenario-vrij)
--   - fact_loonkost (OUTPUT, AFGELEID — nooit handmatig geïnserteerd)
--
-- Design per specs/001-rekencascade/research.md:
--   Decision 1: AFGELEID = REVOKE writes op fact_loonkost + SECURITY DEFINER function
--               als enige schrijfroute (create_loonkost_cascade in T-027)
--   Decision 2: scenario_id op fact_looncomponent + fact_loonkost; NIET op
--               fact_prestatie/fact_wagen (fysieke werkelijkheid is scenario-vrij)
--   Decision 3: periode = date NOT NULL CHECK date_trunc('month', periode) = periode
--   Decision 4: kostenblok CHECK IN 7 canonieke waarden
--
-- RLS pattern: tenant-scoping via dim_contract → dim_legale_entiteit → basejump.account
-- (idem T-006 dim_contract). fact_loonkost heeft ALLEEN select policy; writes zijn
-- REVOKED (AFGELEID-invariant).
--
-- Principe V bewijs: dit is de Green-commit die volgt op de Red pgTAP commit
-- (39-fact-tables.sql — plan(41)). Zonder deze migration faalt pgTAP.


-- ================================================================
-- 1) fact_looncomponent — input, scenario-gebonden
-- ================================================================

create table public.fact_looncomponent (
    fact_looncomponent_id uuid primary key default gen_random_uuid(),
    contract_id uuid not null references public.dim_contract (contract_id) on delete restrict,
    periode date not null check (date_trunc('month', periode) = periode),
    component_id text not null references public.dim_looncomponent (component_id) on delete restrict,
    scenario_id uuid not null references public.dim_scenario (scenario_id) on delete restrict,
    bedrag numeric(18, 4) not null,
    bron_ref text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (contract_id, periode, component_id, scenario_id)
);

comment on table public.fact_looncomponent is
    'Input fact: bedrag per (contract, periode, component, scenario). Cascade groepeert via dim_looncomponent gedragstags (Principe II).';
comment on column public.fact_looncomponent.bedrag is
    'Bedrag in EUR, numeric(18,4) cent-precisie per Constitution v1.0.1. Retro-correcties kunnen negatief zijn — geen positieve CHECK.';
comment on column public.fact_looncomponent.scenario_id is
    'Scenario-gebonden per research.md Decision 2 — loon-componenten kunnen scenario-varianten hebben.';

alter table public.fact_looncomponent enable row level security;

create policy fact_looncomponent_tenant on public.fact_looncomponent
    for all to authenticated
    using (exists (
        select 1
        from public.dim_contract c
        join public.dim_legale_entiteit e using (legale_entiteit_id)
        where c.contract_id = fact_looncomponent.contract_id
          and basejump.has_role_on_account(e.owning_account_id)
    ))
    with check (exists (
        select 1
        from public.dim_contract c
        join public.dim_legale_entiteit e using (legale_entiteit_id)
        where c.contract_id = fact_looncomponent.contract_id
          and basejump.has_role_on_account(e.owning_account_id)
    ));

create index fact_looncomponent_contract_periode_idx
    on public.fact_looncomponent (contract_id, periode);

create trigger fact_looncomponent_set_timestamps
    before insert or update on public.fact_looncomponent
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 2) fact_prestatie — input, scenario-vrij
-- ================================================================

create table public.fact_prestatie (
    fact_prestatie_id uuid primary key default gen_random_uuid(),
    contract_id uuid not null references public.dim_contract (contract_id) on delete restrict,
    periode date not null check (date_trunc('month', periode) = periode),
    prestatiecode_id text not null references public.dim_prestatiecode (prestatiecode) on delete restrict,
    uren numeric(6, 4) not null check (uren >= 0),
    dagen numeric(6, 4) not null check (dagen >= 0),
    bron_ref text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (contract_id, periode, prestatiecode_id)
);

comment on table public.fact_prestatie is
    'Input fact: uren + dagen per (contract, periode, prestatiecode). Scenario-vrij per research.md Decision 2 — fysieke werkelijkheid. Input voor mu = Q/S via dim_prestatiecode.telt_voor_mu filter.';
comment on column public.fact_prestatie.uren is
    'Gewerkte uren, numeric(6,4) breuk-precisie. Cascade filtert op dim_prestatiecode.telt_voor_mu = true voor mu-berekening.';

alter table public.fact_prestatie enable row level security;

create policy fact_prestatie_tenant on public.fact_prestatie
    for all to authenticated
    using (exists (
        select 1
        from public.dim_contract c
        join public.dim_legale_entiteit e using (legale_entiteit_id)
        where c.contract_id = fact_prestatie.contract_id
          and basejump.has_role_on_account(e.owning_account_id)
    ))
    with check (exists (
        select 1
        from public.dim_contract c
        join public.dim_legale_entiteit e using (legale_entiteit_id)
        where c.contract_id = fact_prestatie.contract_id
          and basejump.has_role_on_account(e.owning_account_id)
    ));

create index fact_prestatie_contract_periode_idx
    on public.fact_prestatie (contract_id, periode);

create trigger fact_prestatie_set_timestamps
    before insert or update on public.fact_prestatie
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 3) fact_wagen — input, scenario-vrij
-- ================================================================

create table public.fact_wagen (
    fact_wagen_id uuid primary key default gen_random_uuid(),
    contract_id uuid not null references public.dim_contract (contract_id) on delete restrict,
    periode date not null check (date_trunc('month', periode) = periode),
    catalogus_waarde numeric(18, 4) not null check (catalogus_waarde > 0),
    co2_g_km smallint not null check (co2_g_km between 0 and 500),
    brandstoftype text not null check (
        brandstoftype in ('benzine', 'diesel', 'elektrisch', 'hybride_benzine', 'hybride_diesel', 'lpg', 'cng', 'waterstof')
    ),
    aanschaffingsdatum date not null,
    bron_ref text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (aanschaffingsdatum <= periode),
    unique (contract_id, periode)
);

comment on table public.fact_wagen is
    'Input fact: wagen-attributen per (contract, periode). Scenario-vrij — fysieke werkelijkheid van het voertuig. Input voor CO2-solidariteitsbijdrage en VAA-berekening.';
comment on column public.fact_wagen.co2_g_km is
    'CO2-uitstoot in g/km, smallint discrete integer (idem param_wagen_mobiliteit.referentie_co2). Range 0-500 sanity guard.';
comment on column public.fact_wagen.brandstoftype is
    'Gesloten enum: 8 canonieke brandstoftypes voor VAA-multiplier lookup in cascade.';

alter table public.fact_wagen enable row level security;

create policy fact_wagen_tenant on public.fact_wagen
    for all to authenticated
    using (exists (
        select 1
        from public.dim_contract c
        join public.dim_legale_entiteit e using (legale_entiteit_id)
        where c.contract_id = fact_wagen.contract_id
          and basejump.has_role_on_account(e.owning_account_id)
    ))
    with check (exists (
        select 1
        from public.dim_contract c
        join public.dim_legale_entiteit e using (legale_entiteit_id)
        where c.contract_id = fact_wagen.contract_id
          and basejump.has_role_on_account(e.owning_account_id)
    ));

create index fact_wagen_contract_periode_idx
    on public.fact_wagen (contract_id, periode);

create trigger fact_wagen_set_timestamps
    before insert or update on public.fact_wagen
    for each row execute function basejump.trigger_set_timestamps();


-- ================================================================
-- 4) fact_loonkost — OUTPUT, AFGELEID
-- ================================================================
--
-- AFGELEID-invariant per Constitution Principe III MUST (regel 127):
--   REVOKE writes van authenticated/public/anon. SECURITY DEFINER cascade-function
--   (create_loonkost_cascade — komt in T-027) is de enige canonieke schrijfroute.
--   Postgres owner (postgres) behoudt impliciet INSERT-toegang voor migrations/seed.

create table public.fact_loonkost (
    fact_loonkost_id uuid primary key default gen_random_uuid(),
    contract_id uuid not null references public.dim_contract (contract_id) on delete restrict,
    periode date not null check (date_trunc('month', periode) = periode),
    kostenblok text not null check (
        kostenblok in ('bruto', 'werkgevers_rsz', 'vakantiegeld', 'ejp', 'extralegaal', 'wagen_tco', 'arbeidsongevallen')
    ),
    scenario_id uuid not null references public.dim_scenario (scenario_id) on delete restrict,
    bedrag numeric(18, 4) not null,
    snapshot_batch_id uuid not null,
    cascade_run_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (contract_id, periode, kostenblok, scenario_id)
);

comment on table public.fact_loonkost is
    'OUTPUT fact — AFGELEID door create_loonkost_cascade() function (T-027). Handmatige INSERT/UPDATE/DELETE is REVOKED. Constitution Principe III MUST (regel 127) reproducibility via snapshot_batch_id link naar T-021 audit.';
comment on column public.fact_loonkost.kostenblok is
    '7 canonieke kostenblokken per Constitution Principe III strict separation. Nieuwe kostenblok = schema-migration + review.';
comment on column public.fact_loonkost.snapshot_batch_id is
    'Reproducibility link naar audit_parameter_snapshot.snapshot_batch_id (T-021). GEEN FK-constraint want audit-tabel heeft 11 rijen per batch — semantic-only reference.';

alter table public.fact_loonkost enable row level security;

-- Alleen SELECT policy — geen INSERT/UPDATE/DELETE policy want writes zijn REVOKED
create policy fact_loonkost_read on public.fact_loonkost
    for select to authenticated
    using (exists (
        select 1
        from public.dim_contract c
        join public.dim_legale_entiteit e using (legale_entiteit_id)
        where c.contract_id = fact_loonkost.contract_id
          and basejump.has_role_on_account(e.owning_account_id)
    ));

-- AFGELEID-invariant: geen writes voor authenticated/public/anon
revoke insert, update, delete on public.fact_loonkost from authenticated, public, anon;

-- Cascade-schrijfroute: service_role kan INSERT + UPDATE (voor ON CONFLICT DO UPDATE
-- bij re-run). GEEN DELETE — fact_loonkost is append-only. In T-027 wordt
-- create_loonkost_cascade() de canonieke schrijfroute; deze GRANT laat T-022
-- pgTAP tests slagen voordat de function bestaat.
grant insert, update on public.fact_loonkost to service_role;

create index fact_loonkost_contract_periode_scenario_idx
    on public.fact_loonkost (contract_id, periode, scenario_id);

create trigger fact_loonkost_set_timestamps
    before insert or update on public.fact_loonkost
    for each row execute function basejump.trigger_set_timestamps();
