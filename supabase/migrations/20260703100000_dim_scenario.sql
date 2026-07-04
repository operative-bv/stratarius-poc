-- T-014: dim_scenario — tenant-scoped scenario-catalogus.
--
-- Elke legale entiteit heeft eigen scenarios (actual / what-if / forecast /
-- baseline). fact_looncomponent en fact_loonkost (Phase 5) verwijzen hierheen
-- zodat dezelfde contract × periode meerdere scenario's kan hebben:
-- bv "actual 2024", "voorstel indexatie +2%", "wetsvoorstel doelgroep gehandicapt".
--
-- Tenant scoping: transitive via legale_entiteit_id → dim_legale_entiteit
-- (T-006 dim_contract pattern). uuid PK ipv text: elk tenant kan eigen
-- scenario-namen bedenken zonder inter-tenant conflicts.


create table public.dim_scenario (
    scenario_id uuid primary key default gen_random_uuid(),
    legale_entiteit_id uuid not null references public.dim_legale_entiteit (legale_entiteit_id) on delete restrict,
    naam text not null,
    beschrijving text null,
    kind text not null check (kind in ('actual', 'what_if', 'forecast', 'baseline')),
    geldig_van date null,
    geldig_tot date null,
    check (geldig_tot is null or geldig_van is null or geldig_van < geldig_tot),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on column public.dim_scenario.kind is
    'actual = historische feiten (default) | what_if = ad-hoc scenario | forecast = geplande toekomstige scenario | baseline = referentie voor vergelijking.';
comment on column public.dim_scenario.legale_entiteit_id is
    'Tenant boundary via dim_legale_entiteit.owning_account_id (T-006 pattern). Scenario is eigendom van de legale entiteit; wordt niet gedeeld tussen tenants.';

alter table public.dim_scenario enable row level security;

-- RLS transitive tenant: byte-identical USING + WITH CHECK exists via
-- dim_legale_entiteit.owning_account_id. Matches T-006 dim_contract.
create policy dim_scenario_tenant on public.dim_scenario
    for all
    using (
        exists (
            select 1 from public.dim_legale_entiteit le
            where le.legale_entiteit_id = dim_scenario.legale_entiteit_id
              and basejump.has_role_on_account(le.owning_account_id)
        )
    )
    with check (
        exists (
            select 1 from public.dim_legale_entiteit le
            where le.legale_entiteit_id = dim_scenario.legale_entiteit_id
              and basejump.has_role_on_account(le.owning_account_id)
        )
    );

create index dim_scenario_legale_entiteit_idx on public.dim_scenario (legale_entiteit_id);

create trigger dim_scenario_set_timestamps
    before insert or update on public.dim_scenario
    for each row execute function basejump.trigger_set_timestamps();
