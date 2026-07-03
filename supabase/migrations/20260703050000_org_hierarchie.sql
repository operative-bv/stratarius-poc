-- T-008: organisatie-hiërarchie infrastructuur (4 tabellen).
--
-- Per PDF Laag 1: organisatie-hiërarchieën zijn ONGELIJK en OVERLAPPEND
-- (dus geen boom), vandaar closure-table pattern. Elke hiërarchie-"flavor"
-- (statutair, business, geografisch, kostenplaats) is een aparte topologie
-- over dezelfde org_units.


------------------------------------------------------------
-- dim_hierarchie — globale lookup van 4 canonieke flavors
------------------------------------------------------------

create table public.dim_hierarchie (
    hierarchie_id text primary key,
    name text not null,
    beschrijving text null,
    bron_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.dim_hierarchie is
    'Canonieke flavors van organisatie-hiërarchieën. Global reference — geen tenant scoping. Bron: PDF Laag 1 conceptueel datamodel.';
comment on column public.dim_hierarchie.hierarchie_id is
    'Text PK per flavor. Note: ''kostenplaats'' als flavor = topologie waarin org_units per kostenplaats georganiseerd worden — distinct van dim_org_unit.kind=''kostenplaats'' (node-type = kostenplaats-eenheid).';

alter table public.dim_hierarchie enable row level security;

create policy dim_hierarchie_read_all on public.dim_hierarchie
    for select using (true);

revoke insert, update, delete on public.dim_hierarchie from authenticated, public, anon;

create trigger dim_hierarchie_set_timestamps
    before insert or update on public.dim_hierarchie
    for each row execute function basejump.trigger_set_timestamps();

insert into public.dim_hierarchie (hierarchie_id, name, beschrijving, bron_url) values
    ('statutair', 'Statutaire hiërarchie', 'Juridische org-structuur (legale entiteit → BU → dept → team)', '_supporting-material/Datamodel_werkgeverskost_Belgie.pdf'),
    ('business', 'Business hiërarchie', 'Product/service-lines organisatie', '_supporting-material/Datamodel_werkgeverskost_Belgie.pdf'),
    ('geografisch', 'Geografische hiërarchie', 'Regio/locatie-gebaseerde structuur', '_supporting-material/Datamodel_werkgeverskost_Belgie.pdf'),
    ('kostenplaats', 'Kostenplaats hiërarchie', 'Cost-center topologie voor rapportage', '_supporting-material/Datamodel_werkgeverskost_Belgie.pdf')
on conflict (hierarchie_id) do nothing;


------------------------------------------------------------
-- dim_org_unit — getypeerde knopen in de hiërarchie
------------------------------------------------------------

create table public.dim_org_unit (
    org_unit_id uuid primary key default gen_random_uuid(),
    owning_account_id uuid not null references basejump.accounts (id) on delete restrict,
    kind text not null check (kind in ('legale_entiteit', 'business_unit', 'departement', 'team', 'kostenplaats')),
    name text not null,
    legale_entiteit_id uuid null references public.dim_legale_entiteit (legale_entiteit_id) on delete restrict,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    -- kind='legale_entiteit' iff legale_entiteit_id is not null (biconditional).
    check (
        (kind = 'legale_entiteit' and legale_entiteit_id is not null)
        or (kind <> 'legale_entiteit' and legale_entiteit_id is null)
    )
);

comment on column public.dim_org_unit.kind is
    'Node-type: legale_entiteit | business_unit | departement | team | kostenplaats. Note: ''kostenplaats'' hier = node-type (kostenplaats-eenheid); distinct van dim_hierarchie.hierarchie_id=''kostenplaats'' (flavor).';
comment on column public.dim_org_unit.legale_entiteit_id is
    'Enkel gevuld wanneer kind=''legale_entiteit''. Biconditional CHECK enforced.';

alter table public.dim_org_unit enable row level security;

create policy dim_org_unit_tenant on public.dim_org_unit
    for all
    using (basejump.has_role_on_account(owning_account_id))
    with check (basejump.has_role_on_account(owning_account_id));

create index dim_org_unit_owning_account_idx on public.dim_org_unit (owning_account_id);
create index dim_org_unit_legale_entiteit_idx on public.dim_org_unit (legale_entiteit_id);

create trigger dim_org_unit_set_timestamps
    before insert or update on public.dim_org_unit
    for each row execute function basejump.trigger_set_timestamps();


------------------------------------------------------------
-- bridge_hierarchie — closure table (ancestor × descendant per flavor)
------------------------------------------------------------

create table public.bridge_hierarchie (
    hierarchie_id text not null references public.dim_hierarchie (hierarchie_id) on delete restrict,
    ancestor_org_unit_id uuid not null references public.dim_org_unit (org_unit_id) on delete restrict,
    descendant_org_unit_id uuid not null references public.dim_org_unit (org_unit_id) on delete restrict,
    afstamming smallint not null check (afstamming >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (hierarchie_id, ancestor_org_unit_id, descendant_org_unit_id)
);

comment on table public.bridge_hierarchie is
    'Closure table: elke org_unit heeft (self, self, 0) plus ancestors met correcte depths. Enables O(1) ancestor/descendant queries.';

alter table public.bridge_hierarchie enable row level security;

-- RLS: BEIDE ancestor en descendant moeten binnen tenant liggen (F2).
-- Byte-identical WITH CHECK voorkomt cross-tenant descendant-leak.
create policy bridge_hierarchie_tenant on public.bridge_hierarchie
    for all
    using (
        exists (
            select 1 from public.dim_org_unit
            where org_unit_id = bridge_hierarchie.ancestor_org_unit_id
              and basejump.has_role_on_account(owning_account_id)
        )
        and exists (
            select 1 from public.dim_org_unit
            where org_unit_id = bridge_hierarchie.descendant_org_unit_id
              and basejump.has_role_on_account(owning_account_id)
        )
    )
    with check (
        exists (
            select 1 from public.dim_org_unit
            where org_unit_id = bridge_hierarchie.ancestor_org_unit_id
              and basejump.has_role_on_account(owning_account_id)
        )
        and exists (
            select 1 from public.dim_org_unit
            where org_unit_id = bridge_hierarchie.descendant_org_unit_id
              and basejump.has_role_on_account(owning_account_id)
        )
    );

create index bridge_hierarchie_descendant_idx on public.bridge_hierarchie (hierarchie_id, descendant_org_unit_id);

create trigger bridge_hierarchie_set_timestamps
    before insert or update on public.bridge_hierarchie
    for each row execute function basejump.trigger_set_timestamps();


------------------------------------------------------------
-- map_entiteit_pc_competentie — welke PC per (entiteit, activiteit, categorie), effective-dated
------------------------------------------------------------

create table public.map_entiteit_pc_competentie (
    entiteit_id uuid not null references public.dim_legale_entiteit (legale_entiteit_id) on delete restrict,
    activiteit text not null,
    categorie smallint not null check (categorie in (1, 2, 3)),
    pc_id text not null references public.dim_pc (pc_id) on delete restrict,
    geldig_van date not null,
    geldig_tot date null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (entiteit_id, activiteit, categorie, geldig_van),
    check (geldig_tot is null or geldig_van < geldig_tot)
);

comment on table public.map_entiteit_pc_competentie is
    'Welke paritair comité per (legale entiteit × activiteit × werkgeverscategorie), effective-dated per Principe I. Geërfd door contract bij creatie maar per individu overrideable. Convention: geen overlappende (geldig_van, geldig_tot) intervallen voor dezelfde (entiteit, activiteit, categorie); enforcement via btree_gist buiten POC-scope.';
comment on column public.map_entiteit_pc_competentie.activiteit is
    'NACE-code of vrije tekst voor POC.';

alter table public.map_entiteit_pc_competentie enable row level security;

-- RLS transitive tenant via entiteit_id → dim_legale_entiteit.basejump_account_id (T-006 pattern).
create policy map_entiteit_pc_competentie_tenant on public.map_entiteit_pc_competentie
    for all
    using (
        exists (
            select 1 from public.dim_legale_entiteit le
            where le.legale_entiteit_id = map_entiteit_pc_competentie.entiteit_id
              and basejump.has_role_on_account(le.basejump_account_id)
        )
    )
    with check (
        exists (
            select 1 from public.dim_legale_entiteit le
            where le.legale_entiteit_id = map_entiteit_pc_competentie.entiteit_id
              and basejump.has_role_on_account(le.basejump_account_id)
        )
    );

create index map_entiteit_pc_competentie_temporal_idx
    on public.map_entiteit_pc_competentie (entiteit_id, geldig_van, geldig_tot);

create trigger map_entiteit_pc_competentie_set_timestamps
    before insert or update on public.map_entiteit_pc_competentie
    for each row execute function basejump.trigger_set_timestamps();
