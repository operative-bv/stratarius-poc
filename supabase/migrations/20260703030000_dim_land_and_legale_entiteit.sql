-- T-005: dim_land + dim_legale_entiteit per PDF Laag 1 + Constitution v1.0.1.
--
-- dim_land is een globale lookup (ISO 3166-1 alpha-2). Global read + revoked
-- writes matcht dim_pc (T-007) pattern.
--
-- dim_legale_entiteit is tenant-scoped domain-data. FK basejump_account_id
-- (expliciet naming ipv T-004's generic owning_account_id) omdat de tenant
-- IS een Basejump team-account. Team-only enforcement via trigger — RLS FOR
-- ALL policy blokkeert cross-tenant INSERT via WITH CHECK.
--
-- Bron: ISO 3166-1 registry — https://www.iso.org/iso-3166-country-codes.html


------------------------------------------------------------
-- dim_land — globale lookup
------------------------------------------------------------

create table public.dim_land (
    land_id text primary key check (land_id = upper(land_id) and length(land_id) = 2),
    name text not null,
    bron_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.dim_land is
    'Canonical registry of ISO 3166-1 alpha-2 country codes. Global reference (no tenant scoping). Feeds dim_legale_entiteit.land_id.';
comment on column public.dim_land.land_id is
    'ISO 3166-1 alpha-2 code, uppercase only. Two-letter constraint enforced via CHECK.';

alter table public.dim_land enable row level security;

create policy dim_land_read_all on public.dim_land
    for select using (true);

revoke insert, update, delete on public.dim_land from authenticated, public, anon;

create trigger dim_land_set_timestamps
    before insert or update on public.dim_land
    for each row execute function basejump.trigger_set_timestamps();

insert into public.dim_land (land_id, name, bron_url) values
    ('BE', 'België', 'https://www.iso.org/iso-3166-country-codes.html'),
    ('NL', 'Nederland', 'https://www.iso.org/iso-3166-country-codes.html'),
    ('FR', 'Frankrijk', 'https://www.iso.org/iso-3166-country-codes.html'),
    ('DE', 'Duitsland', 'https://www.iso.org/iso-3166-country-codes.html'),
    ('LU', 'Luxemburg', 'https://www.iso.org/iso-3166-country-codes.html')
on conflict (land_id) do nothing;


------------------------------------------------------------
-- dim_legale_entiteit — tenant-scoped, team-only
------------------------------------------------------------

-- Team-account enforcement per N-007 (deterministic SQLSTATE for pgTAP):
-- Postgres CHECK constraints cannot reference other tables, so this trigger
-- enforces that basejump_account_id points at a TEAM account (not personal).
--
-- SECURITY DEFINER: runs with owner privileges so the trigger sees
-- basejump.accounts regardless of caller's GRANT on that table. Without this,
-- an authenticated tenant user might have SELECT restricted on basejump.accounts,
-- causing the EXISTS to return false and silently accepting a personal-account FK.
--
-- search_path pinned to prevent search-path-based hijacking of `basejump` /
-- `pg_temp` references — standard practice for SECURITY DEFINER functions.
create or replace function public.dim_legale_entiteit_enforce_team_account()
    returns trigger
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
    as $$
begin
    if exists (
        select 1 from basejump.accounts
        where id = new.basejump_account_id and personal_account = true
    ) then
        raise exception 'dim_legale_entiteit basejump_account_id % refers to a personal account; only team accounts are allowed per N-007',
            new.basejump_account_id
            using errcode = '23514';  -- check_violation
    end if;
    return new;
end;
$$;

create table public.dim_legale_entiteit (
    legale_entiteit_id uuid primary key default gen_random_uuid(),
    basejump_account_id uuid not null references basejump.accounts (id) on delete restrict,
    werkgeverscategorie smallint not null check (werkgeverscategorie in (1, 2, 3)),
    ondernemingsnr text
        check (land_id <> 'BE' or ondernemingsnr is null or ondernemingsnr ~ '^[01]\d{3}\.\d{3}\.\d{3}$'),
    naam text not null,
    land_id text not null references public.dim_land (land_id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on column public.dim_legale_entiteit.basejump_account_id is
    'FK to basejump.accounts. Trigger enforces personal_account = false per N-007 team-only decision.';
comment on column public.dim_legale_entiteit.werkgeverscategorie is
    '1 = algemeen/privé · 2 = social profit · 3 = beschutte werkplaats. Data-driven key voor param_rsz + param_structurele_vermindering (Principe II).';
comment on column public.dim_legale_entiteit.ondernemingsnr is
    'KBO nummer. BE-only format: 0XXX.XXX.XXX or 1XXX.XXX.XXX. Andere landen vrij.';

alter table public.dim_legale_entiteit enable row level security;

-- Single FOR ALL RLS met expliciete WITH CHECK — blokkeert cross-tenant INSERT.
create policy dim_legale_entiteit_tenant on public.dim_legale_entiteit
    for all
    using (basejump.has_role_on_account(basejump_account_id))
    with check (basejump.has_role_on_account(basejump_account_id));

create index dim_legale_entiteit_basejump_account_idx
    on public.dim_legale_entiteit (basejump_account_id);

create trigger dim_legale_entiteit_check_team_account
    before insert or update on public.dim_legale_entiteit
    for each row execute function public.dim_legale_entiteit_enforce_team_account();

create trigger dim_legale_entiteit_set_timestamps
    before insert or update on public.dim_legale_entiteit
    for each row execute function basejump.trigger_set_timestamps();
