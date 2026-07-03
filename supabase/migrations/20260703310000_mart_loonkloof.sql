-- T-030: mart_loonkloof materialized view (Phase 6 loonkloof-mart)
--
-- Per PDF Laag 1 MART_LOONKLOOF definitie. Kolommen:
--   persoon_id, referentiedatum (kwartaal-eind), kwartaal (YYYY-QN),
--   uurloon_bruto, basis_vte, variabele_vte, geslacht, functieniveau, ancienniteit_jaren
--
-- Data-driven:
--   basis_vte = SUM(fact_looncomponent.bedrag) WHERE dim_looncomponent.is_basisloon
--   variabele_vte = SUM(bedrag) WHERE rsz_plichtig AND NOT is_basisloon
--   uurloon_bruto via cascade uurloon_van_maandloon(basis_vte, pc_id, referentiedatum)
--
-- Refresh cron in T-031 (nog niet geïmplementeerd). Deze migration definieert de view
-- + unique index maar draait geen REFRESH.
--
-- GDPR: geslacht kolom bevat beschermde categorie. RLS + column-level policies via
-- basejump.has_role_on_account. Access enkel via mart_loonkloof RPC met rechtsgrondslag.

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

comment on materialized view public.mart_loonkloof is
    'Loonkloof-mart per persoon × kwartaal. basis_vte + variabele_vte gesplit (Oaxaca decompositie eist). uurloon_bruto via T-023. GDPR beschermde geslacht kolom vereist rechtsgrondslag per query (T-034 mart_loonkloof RPC). Refresh cron in T-031.';

-- REFRESH is deferred naar T-031 cron. Deze migration definieert alleen de structure.
