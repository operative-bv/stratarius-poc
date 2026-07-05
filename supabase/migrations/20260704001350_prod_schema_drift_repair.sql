-- ================================================================
-- Prod schema drift repair — dicht de gap tussen prod en local.
--
-- Root cause: commit 3d31780 (T-052) rende `basejump_account_id` →
-- `owning_account_id` via *edit-in-place* op historische migrations.
-- Lokaal werkt dat (db reset replay't schema vers), maar prod, waar
-- die migrations al waren toegepast, veranderde niet mee. Zelfde
-- patroon voor `basisfactor_arbeider_pct → basisfactor_pct` en
-- de latere drop van `param_rsz.land_id`.
--
-- Deze migration is IDEMPOTENT — draait op prod = fix, draait op local
-- via `db reset` = no-op (elke actie is conditioneel op drift-detectie).
--
-- Wat we fixen:
--   1. Kolom-renames op dim_legale_entiteit + param_rsz (data-preservend)
--   2. Drop param_rsz.land_id + FK
--   3. Recreate exclusion constraint op param_rsz (zonder land_id)
--   4. RLS policies met correcte kolomnaam (kritisch voor tenant isolatie)
--   5. Views mart_loonkloof + mart_loonkloof_decomp (herbouw)
--   6. Function bodies met correcte kolomnamen
--
-- Wat we NIET fixen (deferred):
--   - Missing check constraints (safety rails, geen blockers)
--   - Grants (identiek in local + prod voor de app werkzame paden)
--
-- ================================================================

-- =========================================================
-- SECTION 1: Kolom renames op dim_legale_entiteit
-- =========================================================
do $$
begin
    if exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'dim_legale_entiteit'
          and column_name = 'basejump_account_id'
    ) then
        -- Rename kolom (data blijft)
        alter table public.dim_legale_entiteit
            rename column basejump_account_id to owning_account_id;

        -- Rename index
        alter index public.dim_legale_entiteit_basejump_account_idx
            rename to dim_legale_entiteit_owning_account_idx;

        -- Rename FK constraint
        alter table public.dim_legale_entiteit
            rename constraint dim_legale_entiteit_basejump_account_id_fkey
            to dim_legale_entiteit_owning_account_id_fkey;

        raise notice 'Renamed dim_legale_entiteit.basejump_account_id → owning_account_id';
    end if;
end $$;

-- =========================================================
-- SECTION 2: Kolom renames op param_rsz + drop land_id
-- =========================================================
do $$
begin
    if exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'param_rsz'
          and column_name = 'basisfactor_arbeider_pct'
    ) then
        alter table public.param_rsz
            rename column basisfactor_arbeider_pct to basisfactor_pct;
        raise notice 'Renamed param_rsz.basisfactor_arbeider_pct → basisfactor_pct';
    end if;
end $$;

do $$
begin
    if exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'param_rsz'
          and column_name = 'land_id'
    ) then
        -- Drop de land-specifieke constraints eerst
        alter table public.param_rsz drop constraint if exists param_rsz_land_id_fkey;
        alter table public.param_rsz drop constraint if exists param_rsz_land_id_status_werkgeverscategorie_daterange_excl;
        alter table public.param_rsz drop column land_id;
        raise notice 'Dropped param_rsz.land_id';
    end if;
end $$;

-- =========================================================
-- SECTION 3: Exclusion constraint op param_rsz (zonder land_id)
-- =========================================================
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.param_rsz'::regclass
          and conname = 'param_rsz_status_werkgeverscategorie_daterange_excl'
    ) then
        alter table public.param_rsz
            add constraint param_rsz_status_werkgeverscategorie_daterange_excl
            exclude using gist (
                status with =,
                werkgeverscategorie with =,
                daterange(geldig_van, coalesce(geldig_tot, 'infinity'::date), '[)') with &&
            );
        raise notice 'Added param_rsz exclusion constraint';
    end if;
end $$;

-- =========================================================
-- SECTION 4: RLS policies met owning_account_id
-- ============================================================
-- Drop + recreate (drop is idempotent, recreate met correcte def).

drop policy if exists dim_legale_entiteit_tenant on public.dim_legale_entiteit;
create policy dim_legale_entiteit_tenant on public.dim_legale_entiteit
    for all
    using (basejump.has_role_on_account(owning_account_id))
    with check (basejump.has_role_on_account(owning_account_id));

drop policy if exists dim_contract_tenant on public.dim_contract;
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

drop policy if exists dim_scenario_tenant on public.dim_scenario;
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

drop policy if exists fact_looncomponent_tenant on public.fact_looncomponent;
create policy fact_looncomponent_tenant on public.fact_looncomponent
    for all
    to authenticated
    using (
        exists (
            select 1 from public.dim_contract c
            join public.dim_legale_entiteit e using (legale_entiteit_id)
            where c.contract_id = fact_looncomponent.contract_id
              and basejump.has_role_on_account(e.owning_account_id)
        )
    )
    with check (
        exists (
            select 1 from public.dim_contract c
            join public.dim_legale_entiteit e using (legale_entiteit_id)
            where c.contract_id = fact_looncomponent.contract_id
              and basejump.has_role_on_account(e.owning_account_id)
        )
    );

drop policy if exists fact_loonkost_read on public.fact_loonkost;
create policy fact_loonkost_read on public.fact_loonkost
    for select
    to authenticated
    using (
        exists (
            select 1 from public.dim_contract c
            join public.dim_legale_entiteit e using (legale_entiteit_id)
            where c.contract_id = fact_loonkost.contract_id
              and basejump.has_role_on_account(e.owning_account_id)
        )
    );

drop policy if exists fact_prestatie_tenant on public.fact_prestatie;
create policy fact_prestatie_tenant on public.fact_prestatie
    for all
    to authenticated
    using (
        exists (
            select 1 from public.dim_contract c
            join public.dim_legale_entiteit e using (legale_entiteit_id)
            where c.contract_id = fact_prestatie.contract_id
              and basejump.has_role_on_account(e.owning_account_id)
        )
    )
    with check (
        exists (
            select 1 from public.dim_contract c
            join public.dim_legale_entiteit e using (legale_entiteit_id)
            where c.contract_id = fact_prestatie.contract_id
              and basejump.has_role_on_account(e.owning_account_id)
        )
    );

drop policy if exists fact_wagen_tenant on public.fact_wagen;
create policy fact_wagen_tenant on public.fact_wagen
    for all
    to authenticated
    using (
        exists (
            select 1 from public.dim_contract c
            join public.dim_legale_entiteit e using (legale_entiteit_id)
            where c.contract_id = fact_wagen.contract_id
              and basejump.has_role_on_account(e.owning_account_id)
        )
    )
    with check (
        exists (
            select 1 from public.dim_contract c
            join public.dim_legale_entiteit e using (legale_entiteit_id)
            where c.contract_id = fact_wagen.contract_id
              and basejump.has_role_on_account(e.owning_account_id)
        )
    );

drop policy if exists map_entiteit_pc_competentie_tenant on public.map_entiteit_pc_competentie;
create policy map_entiteit_pc_competentie_tenant on public.map_entiteit_pc_competentie
    for all
    using (
        exists (
            select 1 from public.dim_legale_entiteit le
            where le.legale_entiteit_id = map_entiteit_pc_competentie.entiteit_id
              and basejump.has_role_on_account(le.owning_account_id)
        )
    )
    with check (
        exists (
            select 1 from public.dim_legale_entiteit le
            where le.legale_entiteit_id = map_entiteit_pc_competentie.entiteit_id
              and basejump.has_role_on_account(le.owning_account_id)
        )
    );

-- =========================================================
-- SECTION 5: Trigger function met owning_account_id
-- =========================================================
create or replace function public.dim_legale_entiteit_enforce_team_account()
    returns trigger
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $fn$
begin
    if exists (
        select 1 from basejump.accounts
        where id = new.owning_account_id and personal_account = true
    ) then
        raise exception 'dim_legale_entiteit owning_account_id % refers to a personal account; only team accounts are allowed per N-007',
            new.owning_account_id
            using errcode = '23514';
    end if;
    return new;
end;
$fn$;

-- =========================================================
-- SECTION 6: cascade functions met basisfactor_pct
-- =========================================================
create or replace function public.cascade_stap2_basis_patronale_rsz(
    p_rsz_grondslag numeric,
    p_status text,
    p_werkgeverscategorie smallint,
    p_periode date
)
    returns numeric
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $fn$
    select (
        p_rsz_grondslag
      * pr.basisbijdrage_pct
      * pr.basisfactor_pct
    )::numeric(18, 4)
    from public.param_rsz pr
    where pr.status               = p_status
      and pr.werkgeverscategorie  = p_werkgeverscategorie
      and p_periode              >= pr.geldig_van
      and (pr.geldig_tot is null or p_periode < pr.geldig_tot);
$fn$;

-- =========================================================
-- SECTION 7: mart_loonkloof + mart_loonkloof_decomp herbouw
-- =========================================================
-- Dependencies: decomp view + mart_loonkloof_decomp_read function verwijzen naar mart_loonkloof.
-- CASCADE dropt beide zodat we ze in de juiste volgorde recreaten.

drop materialized view if exists public.mart_loonkloof cascade;

create materialized view public.mart_loonkloof as
with
    kwartaal_eindes as (
        select generate_series('2024-03-31'::date, '2024-12-31'::date, interval '3 months')::date as referentiedatum
    ),
    contract_op_referentie as (
        select
            c.contract_id, c.persoon_id, c.pc_id, c.geldig_van, c.legale_entiteit_id,
            f.functieniveau,
            p.geslacht,
            k.referentiedatum
        from public.dim_contract c
        join public.dim_functie f on f.functie_id = c.functie_id
        join public.dim_persoon p on p.persoon_id = c.persoon_id
        cross join kwartaal_eindes k
        where c.geldig_van <= k.referentiedatum
          and (c.geldig_tot is null or c.geldig_tot > k.referentiedatum)
    ),
    lonen_maand as (
        select
            cr.persoon_id, cr.referentiedatum, cr.pc_id, cr.functieniveau, cr.geslacht,
            cr.geldig_van, cr.legale_entiteit_id,
            coalesce(sum(fl.bedrag) filter (where dl.is_basisloon), 0)::numeric(18, 4) as basis_vte,
            coalesce(sum(fl.bedrag) filter (where dl.rsz_plichtig and not dl.is_basisloon), 0)::numeric(18, 4) as variabele_vte
        from contract_op_referentie cr
        left join public.fact_looncomponent fl
            on fl.contract_id = cr.contract_id
            and fl.periode = date_trunc('month', cr.referentiedatum)::date
            and fl.scenario_id in (
                select s.scenario_id from public.dim_scenario s
                where s.kind = 'baseline'
                  and s.legale_entiteit_id = cr.legale_entiteit_id
            )
        left join public.dim_looncomponent dl on dl.component_id = fl.component_id
        group by cr.persoon_id, cr.referentiedatum, cr.pc_id, cr.functieniveau, cr.geslacht, cr.geldig_van, cr.legale_entiteit_id
    )
select
    lm.persoon_id,
    lm.legale_entiteit_id,
    lm.referentiedatum,
    extract(year from lm.referentiedatum)::text || '-Q' || extract(quarter from lm.referentiedatum)::text as kwartaal,
    public.uurloon_van_maandloon(lm.basis_vte, lm.pc_id, lm.referentiedatum) as uurloon_bruto,
    lm.basis_vte,
    lm.variabele_vte,
    lm.geslacht,
    lm.functieniveau,
    round(((lm.referentiedatum - lm.geldig_van)::numeric / 365.25), 2)::numeric(6, 2) as ancienniteit_jaren
from lonen_maand lm;

create unique index mart_loonkloof_pk on public.mart_loonkloof (persoon_id, referentiedatum);
create index mart_loonkloof_legale_entiteit_idx on public.mart_loonkloof (legale_entiteit_id);

create or replace view public.mart_loonkloof_decomp as
with pop as (
    select
        m.legale_entiteit_id,
        m.referentiedatum,
        m.kwartaal,
        m.persoon_id,
        m.geslacht,
        m.functieniveau,
        m.uurloon_bruto,
        m.ancienniteit_jaren,
        case
            when m.ancienniteit_jaren < 2 then 'junior'
            when m.ancienniteit_jaren < 5 then 'medior'
            else 'senior'
        end as ancienniteit_bucket,
        p.opleidingsniveau
    from public.mart_loonkloof m
    join public.dim_persoon p on p.persoon_id = m.persoon_id
),
stratum_stats as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        functieniveau, opleidingsniveau, ancienniteit_bucket, geslacht,
        avg(uurloon_bruto) as avg_uurloon,
        count(*)::int as n,
        coalesce(var_samp(uurloon_bruto), 0) as var_uurloon
    from pop
    group by legale_entiteit_id, referentiedatum, kwartaal,
             functieniveau, opleidingsniveau, ancienniteit_bucket, geslacht
),
per_periode as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        avg(uurloon_bruto) filter (where geslacht = 'm') as gem_uurloon_m,
        avg(uurloon_bruto) filter (where geslacht = 'v') as gem_uurloon_v,
        count(*) filter (where geslacht = 'm')::int as n_m,
        count(*) filter (where geslacht = 'v')::int as n_v,
        coalesce(var_samp(uurloon_bruto) filter (where geslacht = 'm'), 0) as var_m,
        coalesce(var_samp(uurloon_bruto) filter (where geslacht = 'v'), 0) as var_v
    from pop
    group by legale_entiteit_id, referentiedatum, kwartaal
),
strata_match as (
    select
        s_m.legale_entiteit_id, s_m.referentiedatum, s_m.kwartaal,
        (s_m.avg_uurloon - s_v.avg_uurloon) as stratum_gap,
        (s_m.n + s_v.n) as stratum_weight
    from stratum_stats s_m
    join stratum_stats s_v
        using (legale_entiteit_id, referentiedatum, kwartaal,
               functieniveau, opleidingsniveau, ancienniteit_bucket)
    where s_m.geslacht = 'm' and s_v.geslacht = 'v'
),
controlled as (
    select
        legale_entiteit_id, referentiedatum, kwartaal,
        sum(stratum_gap * stratum_weight) / nullif(sum(stratum_weight), 0) as residual_gap,
        sum(stratum_weight)::int as matched_pop_size
    from strata_match
    group by legale_entiteit_id, referentiedatum, kwartaal
)
select
    p.legale_entiteit_id,
    p.referentiedatum,
    p.kwartaal,
    p.n_m,
    p.n_v,
    round(p.gem_uurloon_m::numeric, 4) as gem_uurloon_m,
    round(p.gem_uurloon_v::numeric, 4) as gem_uurloon_v,
    round((p.gem_uurloon_m - p.gem_uurloon_v)::numeric, 4) as raw_gap,
    round(coalesce(c.residual_gap, 0)::numeric, 4) as residual_gap,
    round(((p.gem_uurloon_m - p.gem_uurloon_v) - coalesce(c.residual_gap, 0))::numeric, 4) as endowment_gap,
    round(
        (1.96 * sqrt(
            case when p.n_m > 0 then p.var_m / p.n_m else 0 end +
            case when p.n_v > 0 then p.var_v / p.n_v else 0 end
        ))::numeric,
        4
    ) as raw_gap_ci95_halfwidth,
    coalesce(c.matched_pop_size, 0) as matched_stratum_pop
from per_periode p
left join controlled c using (legale_entiteit_id, referentiedatum, kwartaal);

-- Refresh materialized view (kan leeg zijn — dat is prima)
refresh materialized view public.mart_loonkloof;

comment on materialized view public.mart_loonkloof is
    'Loonkloof-mart per persoon × kwartaal. Herbouwd door prod_schema_drift_repair.';
