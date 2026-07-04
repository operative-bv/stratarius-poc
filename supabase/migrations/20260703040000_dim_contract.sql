-- T-006: dim_contract — ruggengraat van het datamodel.
--
-- Verbindt persoon (T-004), functie (T-004), legale entiteit (T-005), en
-- paritair comité (T-007) tot een effective-dated versie-keten. Alle Phase 5
-- fact-tables verwijzen straks naar dim_contract via contract_id.
--
-- Constitution Principe I (Effective-Dating Everywhere, NON-NEGOTIABLE) is
-- hier expliciet van toepassing: geldig_van NOT NULL, geldig_tot NULL open-
-- ended, uitgestelde wetgeving toegestaan.
--
-- Principe IV: mu (effectieve prestatiebreuk μ = Q/S) is BEWUST afwezig op
-- deze tabel — die wordt derived in fact_prestatie (T-024). Op dim_contract
-- zit ENKEL fte_breuk (juridische tewerkstellingsbreuk).
--
-- UPDATE-restriction convention: wijzigingen aan status/fte_breuk/pc_id/
-- functie_id/legale_entiteit_id/persoon_id/geldig_van moeten een NIEUWE rij
-- worden met vorige_contract_id link. UPDATE op deze kolommen is convention-
-- verboden; database-enforcement via trigger blijft future work (aparte
-- ticket wanneer code-review drift blijkt).


create table public.dim_contract (
    contract_id uuid primary key default gen_random_uuid(),

    persoon_id uuid not null references public.dim_persoon (persoon_id) on delete restrict,
    functie_id uuid not null references public.dim_functie (functie_id) on delete restrict,
    legale_entiteit_id uuid not null references public.dim_legale_entiteit (legale_entiteit_id) on delete restrict,
    pc_id text not null references public.dim_pc (pc_id) on delete restrict,

    status text not null check (status in ('arbeider', 'bediende')),
    fte_breuk numeric(6, 4) not null check (fte_breuk > 0 and fte_breuk <= 1),

    geldig_van date not null,
    geldig_tot date null,
    check (geldig_tot is null or geldig_van < geldig_tot),

    vorige_contract_id uuid null references public.dim_contract (contract_id) on delete restrict,
    reden text null,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.dim_contract is
    'Ruggengraat van het datamodel. Verbindt persoon, functie, legale entiteit en pc tot een effective-dated versie-keten per Constitution Principe I. WIJZIGINGEN (indexering, promotie, urenwijziging, status-change) zijn convention NIEUWE rijen met vorige_contract_id link — geen UPDATE.';
comment on column public.dim_contract.fte_breuk is
    'Juridische tewerkstellingsbreuk (0 < x <= 1). Constitution v1.0.1 non-money precision. Principe IV: strict gescheiden van mu (effectieve prestatiebreuk); mu leeft op fact_prestatie (T-024), NIET hier.';
comment on column public.dim_contract.geldig_van is
    'Startdatum van deze contract-versie. NOT NULL per Principe I. Uitgestelde wetgeving toegestaan: geldig_van > current_date is geldig voor forecasting.';
comment on column public.dim_contract.geldig_tot is
    'Einddatum. NULL = open einde (huidig contract). Per Principe I: nieuwe versie = INSERT met vorige_contract_id link en UPDATE geldig_tot op de voorganger.';
comment on column public.dim_contract.vorige_contract_id is
    'Self-FK naar de voorgaande contract-versie in de keten. NULL = eerste versie in de keten (nieuwe indiensttreding).';
comment on column public.dim_contract.reden is
    'Beschrijft welke gebeurtenis deze versie triggerde: indexering, promotie, urenwijziging, status_change, correctie. Free text voor POC; enum in future enhancement.';
comment on column public.dim_contract.status is
    'arbeider | bediende. Belgische sociale statuten post-2014 unificatie. Feed voor param_rsz (basisfactor 108% voor arbeiders per PDF Laag 3) en param_vakantiegeld (regime-split).';

alter table public.dim_contract enable row level security;

-- RLS pattern deviation from T-004/T-005: dim_contract has no direct
-- owning_account_id. Tenant identity is transitive via legale_entiteit_id →
-- dim_legale_entiteit.owning_account_id. DELIBERATE: do NOT normalize by
-- adding a redundant owning_account_id column — the transitivity is the
-- correct model (a legale entiteit BELONGS to one tenant; contracts belong to
-- the same tenant through the entiteit).
--
-- USING clause is byte-identical to WITH CHECK: both filter existing rows
-- and validate new rows. Postgres optimizes EXISTS to a semi-join; with
-- index on dim_contract.legale_entiteit_id and dim_legale_entiteit's PK
-- this is fast.
create policy dim_contract_tenant on public.dim_contract
    for all
    using (
        exists (
            select 1 from public.dim_legale_entiteit le
            where le.legale_entiteit_id = dim_contract.legale_entiteit_id
              and basejump.has_role_on_account(le.owning_account_id)
        )
    )
    with check (
        exists (
            select 1 from public.dim_legale_entiteit le
            where le.legale_entiteit_id = dim_contract.legale_entiteit_id
              and basejump.has_role_on_account(le.owning_account_id)
        )
    );

-- Backing indexes for RLS predicate + downstream cascade joins.
create index dim_contract_legale_entiteit_idx on public.dim_contract (legale_entiteit_id);
create index dim_contract_persoon_idx on public.dim_contract (persoon_id);
create index dim_contract_geldig_idx on public.dim_contract (geldig_van, geldig_tot);
create index dim_contract_vorige_idx on public.dim_contract (vorige_contract_id);

create trigger dim_contract_set_timestamps
    before insert or update on public.dim_contract
    for each row execute function basejump.trigger_set_timestamps();
