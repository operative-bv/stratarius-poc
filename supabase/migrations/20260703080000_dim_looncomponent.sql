-- T-011: dim_looncomponent — schema + gedragstags (geen seed; T-012 doet dat).
--
-- Belichaamt Principe II: rekencascade leest gedragstags (rsz_plichtig,
-- is_werkgeverskost, telt_voor_vakantiegeld, sz_behandeling_id, telt_voor_mu)
-- om te weten HOE een component zich gedraagt — NOOIT via component identity.
-- Geen `if component_id = 'basisloon'` in de cascade. Alle branching gaat
-- via de tags.
--
-- Bron: RSZ instructiegids + KB's + sector-CAOs (per component in seed).


create table public.dim_looncomponent (
    component_id text primary key,
    name text not null,
    familie text not null,

    -- Gedragstags — Principe II. Alle NOT NULL zonder default: dwingt seed
    -- expliciet te zetten, voorkomt 'vergeten' tags.
    rsz_plichtig boolean not null,
    is_werkgeverskost boolean not null,
    telt_voor_vakantiegeld boolean not null,
    sz_behandeling_id text not null references public.dim_sz_behandeling (sz_behandeling_id) on delete restrict,
    telt_voor_mu boolean not null,

    bron_url text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.dim_looncomponent is
    'Loonvormen-catalogus met gedragstags. Global reference. Rekencascade (Phase 5) leest gedragstags via fact_looncomponent.component_id FK; NOOIT switching op name of id. Seed levert T-012 met VAA-valkuil-test.';

comment on column public.dim_looncomponent.rsz_plichtig is
    'Principe II gedragstag: is component subject to werkgevers-RSZ? Rekencascade stap 2 leest deze bool om te bepalen of component in RSZ-grondslag telt.';
comment on column public.dim_looncomponent.is_werkgeverskost is
    'Principe II gedragstag: telt component mee als werkgeverskost? Kritisch voor VAA-valkuil: bedrijfswagen-VAA = false (fiscale waardering voor werknemer, geen kost werkgever), bedrijfswagen-TCO = true. T-012 seed test dit expliciet.';
comment on column public.dim_looncomponent.telt_voor_vakantiegeld is
    'Principe II gedragstag: telt component mee voor vakantiegeld-provisie in cascade stap 6? Basisloon = true, meestal extralegale voordelen = false.';
comment on column public.dim_looncomponent.sz_behandeling_id is
    'Principe II FK naar dim_sz_behandeling. Bepaalt via welk SZ-regime component wordt behandeld (Normaal, VIN forfaitair, etc). Cascade leest sz_behandeling en verwerkt component per regime-gedragstype — nooit via component identity.';
comment on column public.dim_looncomponent.telt_voor_mu is
    'Principe II gedragstag: telt component uur mee voor mu = Q/S (effectieve prestatiebreuk)? Doorgaans false voor bedragen (extralegale voordelen), true voor loon-per-uur componenten.';

alter table public.dim_looncomponent enable row level security;

create policy dim_looncomponent_read_all on public.dim_looncomponent
    for select using (true);

revoke insert, update, delete on public.dim_looncomponent from authenticated, public, anon;

create index dim_looncomponent_sz_behandeling_idx on public.dim_looncomponent (sz_behandeling_id);

create trigger dim_looncomponent_set_timestamps
    before insert or update on public.dim_looncomponent
    for each row execute function basejump.trigger_set_timestamps();
