-- T-004: dim_persoon and dim_functie per PDF Laag 1 + Constitution v1.0.1.
--
-- Tenant scoping via basejump accounts + basejump.has_role_on_account().
-- Effective-dating deferred: attributes considered stable for POC. If real-world
-- opleidingsniveau changes require versioning, SCD Type 2 in a follow-up migration.
-- GDPR: geslacht + opleidingsniveau column-SELECT revoked from authenticated;
--   T-034 (GDPR-audit RPC) grants access via SECURITY DEFINER function.
-- ON DELETE RESTRICT on owning_account_id: audit preservation. CASCADE would
--   destroy audit trail; SET NULL would orphan tenant-scoped rows without RLS
--   anchor. RESTRICT forces explicit data-migration on team offboarding.


create table public.dim_persoon (
    persoon_id uuid primary key default gen_random_uuid(),
    owning_account_id uuid not null references basejump.accounts (id) on delete restrict,
    geslacht text check (geslacht in ('m', 'v', 'x')),
    geboortedatum date not null check (
        geboortedatum <= current_date and geboortedatum >= date '1900-01-01'
    ),
    opleidingsniveau text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on column public.dim_persoon.geslacht is
    'GDPR: beschermde categorie. Column-SELECT revoked from authenticated. Toegang enkel via mart_loonkloof RPC met rechtsgrondslag (T-034).';
comment on column public.dim_persoon.opleidingsniveau is
    'GDPR: verklarende categorie voor loonkloof-analyse (Oaxaca-controls). Zelfde access-regels als geslacht.';
comment on column public.dim_persoon.geboortedatum is
    'Leidt leeftijd af (leeftijdsgebonden verminderingen, VAA-berekening, OLS-controle). Sanity: 1900 <= x <= today.';

alter table public.dim_persoon enable row level security;

-- RLS: single FOR ALL policy with explicit WITH CHECK. USING filters existing
-- rows for SELECT/UPDATE/DELETE; WITH CHECK enforces the new row's tenant on
-- INSERT/UPDATE — prevents cross-tenant INSERTs even if user has role on some
-- account.
create policy dim_persoon_tenant on public.dim_persoon
    for all
    using (basejump.has_role_on_account(owning_account_id))
    with check (basejump.has_role_on_account(owning_account_id));

-- Supporting index for RLS predicate: without this, has_role_on_account
-- forces seq scan on every filtered query.
create index dim_persoon_owning_account_idx on public.dim_persoon (owning_account_id);

-- GDPR column-level enforcement (T-004 F3): revoke SELECT of protected columns
-- from authenticated role. T-034 grants back via SECURITY DEFINER RPC that logs
-- rechtsgrondslag per query per Constitution Domain sectie.
revoke select (geslacht, opleidingsniveau) on public.dim_persoon from authenticated;

-- Trigger fires on INSERT+UPDATE matching Basejump's timestamp-bump pattern.
-- The BEFORE INSERT branch is redundant given column defaults but is kept for
-- consistency with basejump.accounts (20240414161947_basejump-accounts.sql:137).
create trigger dim_persoon_set_timestamps
    before insert or update on public.dim_persoon
    for each row execute function basejump.trigger_set_timestamps();


create table public.dim_functie (
    functie_id uuid primary key default gen_random_uuid(),
    owning_account_id uuid not null references basejump.accounts (id) on delete restrict,
    functienaam text not null,
    functieniveau smallint check (functieniveau between 1 and 30),
    genderneutrale_weging numeric(12, 8),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on column public.dim_functie.functieniveau is
    'Vergelijkingsgroep voor Oaxaca-decompositie (T-051). Praktisch 1-25 in Hay/Berenschot classifications.';
comment on column public.dim_functie.genderneutrale_weging is
    'Dimensieloze coefficient per Constitution v1.0.1 non-money precision policy (numeric(12,8)). Voedt gender-neutrale weging van functie in loonkloof-analyse.';

alter table public.dim_functie enable row level security;

create policy dim_functie_tenant on public.dim_functie
    for all
    using (basejump.has_role_on_account(owning_account_id))
    with check (basejump.has_role_on_account(owning_account_id));

create index dim_functie_owning_account_idx on public.dim_functie (owning_account_id);

create trigger dim_functie_set_timestamps
    before insert or update on public.dim_functie
    for each row execute function basejump.trigger_set_timestamps();
