-- T-027 HOTFIX B: dim_persoon_arbeidsverleden voor werkloos_min_maanden voorwaarde
begin;

create table public.dim_persoon_arbeidsverleden (
    arbeidsverleden_id uuid primary key default gen_random_uuid(),
    persoon_id uuid not null references public.dim_persoon (persoon_id) on delete restrict,
    owning_account_id uuid not null references basejump.accounts (id) on delete restrict,
    werkloosheidsperiode_van date not null,
    werkloosheidsperiode_tot date null,
    bron text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (werkloosheidsperiode_tot is null or werkloosheidsperiode_van < werkloosheidsperiode_tot)
);

alter table public.dim_persoon_arbeidsverleden enable row level security;

create policy dim_persoon_arbeidsverleden_tenant on public.dim_persoon_arbeidsverleden
    for all to authenticated
    using (basejump.has_role_on_account(owning_account_id))
    with check (basejump.has_role_on_account(owning_account_id));

create index dim_persoon_arbeidsverleden_persoon_idx on public.dim_persoon_arbeidsverleden (persoon_id);

commit;

comment on table public.dim_persoon_arbeidsverleden is
    'Werkloosheidsverleden per persoon voor doelgroepverminderingen (cascade stap 4). Elke rij = één werkloosheidsperiode. werkloosheidsperiode_tot=NULL = nog werkloos (mag geen contract hebben in die periode). Cascade stap 4 sommeert maanden-in-periodes VÓÓR dienstverband_van voor werkloos_min_maanden matching.';
