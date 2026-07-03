-- T-007: dim_pc — canonical registry of Belgian Paritaire Comités.
--
-- Global reference table: geen tenant scoping. Elke authenticated user leest;
-- writes uitsluitend via service_role (import scripts, admin). Feeds
-- dim_contract.pc_id, param_sectorbijdrage, param_arbeidsduur, en
-- map_entiteit_pc_competentie in latere tickets.
-- Bron: FOD WASO PC-register — https://werk.belgie.be/nl/themas/paritaire-comites

create table public.dim_pc (
    pc_id text primary key,
    name text not null,
    sector text,
    parent_pc_id text references public.dim_pc (pc_id) on delete restrict,
    status text not null default 'active' check (status in ('active', 'deprecated')),
    bron_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.dim_pc is
    'Canonical registry of Belgian Paritaire Comités. Global reference (no tenant scoping). Feeds dim_contract.pc_id, param_sectorbijdrage, param_arbeidsduur, map_entiteit_pc_competentie. Bron: FOD WASO PC-register.';
comment on column public.dim_pc.parent_pc_id is
    'Self-FK voor sub-comités (bv 200.01 -> parent 200). NULL for top-level PCs.';
comment on column public.dim_pc.status is
    'active | deprecated. Deprecated PCs blijven voor historisch dim_contract-referenties.';

alter table public.dim_pc enable row level security;

-- Global read for authenticated. Anon role has no matching policy → blocked.
create policy dim_pc_read_all on public.dim_pc
    for select using (true);

-- Writes disabled for authenticated + defense-in-depth for public and anon.
-- service_role bypasses RLS in Supabase.
revoke insert, update, delete on public.dim_pc from authenticated, public, anon;

create index dim_pc_parent_idx on public.dim_pc (parent_pc_id);

create trigger dim_pc_set_timestamps
    before insert or update on public.dim_pc
    for each row execute function basejump.trigger_set_timestamps();

-- Seed 11 gangbare PCs. ON CONFLICT DO NOTHING (F7) — defensive tegen
-- partial-apply of toekomstige migration die same PCs opnieuw insert.
insert into public.dim_pc (pc_id, name, sector, bron_url) values
    ('100', 'Aanvullend paritair comité voor werklieden', 'Algemeen', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('111', 'Metaal-, machine- en elektrische bouw', 'Metaal', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('118', 'Voedingsnijverheid arbeiders', 'Voeding', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('124', 'Bouwbedrijf', 'Bouw', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('200', 'Aanvullend paritair comité voor bedienden', 'Algemeen', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('201', 'Zelfstandige detailhandel', 'Retail', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('209', 'Bedienden van de metaalfabrikatennijverheid', 'Metaal', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('220', 'Voedingsnijverheid bedienden', 'Voeding', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('302', 'Hotelbedrijf', 'Horeca', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('314', 'Kappersbedrijf en schoonheidszorgen', 'Persoonlijke verzorging', 'https://werk.belgie.be/nl/themas/paritaire-comites'),
    ('322', 'Uitzendarbeid', 'Interim', 'https://werk.belgie.be/nl/themas/paritaire-comites')
on conflict (pc_id) do nothing;
