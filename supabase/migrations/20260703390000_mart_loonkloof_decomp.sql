-- T-033: mart_loonkloof_decomp view + RPC (stratified Kitagawa-decompositie)
--
-- Design: pure Postgres kan geen multivariate OLS zonder MADlib/PL-R. In plaats
-- van coëfficiënt-gebaseerde Oaxaca-Blinder (β_m, β_v via regressie) doet deze view
-- een **stratified Kitagawa-decompositie** die dezelfde conceptuele splitsing levert:
--
--   raw_gap        = gem_M - gem_V
--   residual_gap   = weighted avg van (gem_M - gem_V) BINNEN elk stratum
--                    (functieniveau × opleidingsniveau × ancienniteit_bucket)
--   endowment_gap  = raw_gap - residual_gap
--                    = compositie-effect (verschil in observables tussen M en V)
--
-- Confidence interval via normale benadering: 1.96 × sqrt(var_m/n_m + var_v/n_v).
--
-- Volwaardige Oaxaca-Blinder met per-coëfficiënt CI komt later via edge function
-- (statsmodels / R). Voor POC-demo is stratified voldoende narratief-krachtig.
--
-- GDPR: `geslacht` blijft beschermd — mart_loonkloof_decomp is een niet-gematerialized
-- view die live queryt op mart_loonkloof. Alleen benaderd via RPC met rechtsgrondslag.

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
    -- Voor elk stratum met BEIDE genders: binnen-stratum gap × weight
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
    -- 95% CI half-width voor raw gap via normale benadering
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

comment on view public.mart_loonkloof_decomp is
    'Stratified Kitagawa-decompositie voor loonkloof per legale_entiteit × kwartaal. raw_gap = endowment_gap + residual_gap. Strata: functieniveau × opleidingsniveau × ancienniteit_bucket. CI via normale benadering. Volwaardige Oaxaca-Blinder met OLS-coefficients deferred naar edge function (R/Python).';

-- RLS-safe RPC (rechtsgrondslag verplicht + auth guard)
create or replace function public.mart_loonkloof_decomp_read(
    p_rechtsgrondslag text,
    p_legale_entiteit_id uuid default null,
    p_kwartaal text default null
)
    returns setof public.mart_loonkloof_decomp
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_initiator uuid;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'mart_loonkloof_decomp_read: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'mart_loonkloof_decomp_read: p_rechtsgrondslag is verplicht (GDPR audit)'
            using errcode = '22023';
    end if;

    -- Audit trail
    insert into public.gdpr_access_log (initiator_user_id, resource, rechtsgrondslag)
    values (v_initiator, 'mart_loonkloof_decomp', p_rechtsgrondslag);

    return query
        select d.*
        from public.mart_loonkloof_decomp d
        where (p_legale_entiteit_id is null or d.legale_entiteit_id = p_legale_entiteit_id)
          and (p_kwartaal is null or d.kwartaal = p_kwartaal);
end;
$$;

comment on function public.mart_loonkloof_decomp_read(text, uuid, text) is
    'Rechtsgrondslag-gated read op mart_loonkloof_decomp. Logs elke read naar gdpr_access_log. Optionele filters legale_entiteit_id + kwartaal.';

revoke execute on function public.mart_loonkloof_decomp_read(text, uuid, text) from public;
grant execute on function public.mart_loonkloof_decomp_read(text, uuid, text) to authenticated;
