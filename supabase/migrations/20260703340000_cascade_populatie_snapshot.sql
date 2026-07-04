-- T-039 (populatie snapshot): één query die cascade output voor alle
-- contracten in caller's tenant × periode berekent. Voorkomt N+1 client-side loop.
--
-- Filter via RLS: user ziet alleen contracten waar has_role_on_account(owning_account_id).

create or replace function public.cascade_populatie_snapshot(
    p_periode date,
    p_scenario_id uuid default null,
    p_functie_id uuid default null
)
    returns table (
        contract_id uuid,
        persoon_id uuid,
        pc_id text,
        status text,
        werkgeverscategorie smallint,
        functienaam text,
        bruto numeric(18, 4),
        stap2_basis_rsz numeric(18, 4),
        stap3_vermindering numeric(18, 4),
        stap5_bijzondere numeric(18, 4),
        stap6_vakantiegeld numeric(18, 4),
        stap7_extralegaal numeric(18, 4),
        totaal_patronale_kost numeric(18, 4),
        tco numeric(18, 4)
    )
    language sql stable parallel safe
    set search_path = public, pg_temp
as $$
    with contracten as (
        select
            c.contract_id,
            c.persoon_id,
            c.pc_id,
            c.status,
            le.werkgeverscategorie,
            f.functienaam,
            -- Bruto per contract per periode (basisloon)
            coalesce((
                select sum(fl.bedrag)
                from public.fact_looncomponent fl
                join public.dim_looncomponent dl on dl.component_id = fl.component_id
                where fl.contract_id = c.contract_id
                  and fl.periode = date_trunc('month', p_periode)::date
                  and (p_scenario_id is null or fl.scenario_id = p_scenario_id)
                  and dl.is_basisloon
            ), 0)::numeric(18, 4) as bruto
        from public.dim_contract c
        join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id
        join public.dim_functie f on f.functie_id = c.functie_id
        where c.geldig_van <= p_periode
          and (c.geldig_tot is null or c.geldig_tot > p_periode)
          and (p_functie_id is null or c.functie_id = p_functie_id)
    )
    select
        c.contract_id,
        c.persoon_id,
        c.pc_id,
        c.status,
        c.werkgeverscategorie,
        c.functienaam,
        c.bruto,
        coalesce(public.cascade_stap2_basis_patronale_rsz(c.bruto, c.status, c.werkgeverscategorie, p_periode), 0)::numeric(18, 4) as stap2_basis_rsz,
        coalesce(public.cascade_stap3_structurele_vermindering(c.bruto * 3, 1.0000, c.werkgeverscategorie, p_periode), 0)::numeric(18, 4) as stap3_vermindering,
        coalesce(public.cascade_stap5_bijzondere_bijdragen(c.bruto, p_periode), 0)::numeric(18, 4) as stap5_bijzondere,
        coalesce(public.cascade_stap6_vakantiegeld(c.bruto, c.status, p_periode), 0)::numeric(18, 4) as stap6_vakantiegeld,
        coalesce((
            select sum(fl.bedrag * pe.taks_pct)
            from public.fact_looncomponent fl
            join public.dim_looncomponent dl on dl.component_id = fl.component_id
            join public.param_extralegaal pe on pe.voordeeltype = dl.component_id
            where fl.contract_id = c.contract_id
              and fl.periode = date_trunc('month', p_periode)::date
              and (p_scenario_id is null or fl.scenario_id = p_scenario_id)
              and dl.familie = 'extralegaal'
              and p_periode >= pe.geldig_van
              and (pe.geldig_tot is null or p_periode < pe.geldig_tot)
        ), 0)::numeric(18, 4) as stap7_extralegaal,
        -- Totaal patronale kost (stap 2 - stap 3 + stap 5 + stap 6 + stap 7)
        (
            coalesce(public.cascade_stap2_basis_patronale_rsz(c.bruto, c.status, c.werkgeverscategorie, p_periode), 0)
            - coalesce(public.cascade_stap3_structurele_vermindering(c.bruto * 3, 1.0000, c.werkgeverscategorie, p_periode), 0)
            + coalesce(public.cascade_stap5_bijzondere_bijdragen(c.bruto, p_periode), 0)
            + coalesce(public.cascade_stap6_vakantiegeld(c.bruto, c.status, p_periode), 0)
        )::numeric(18, 4) as totaal_patronale_kost,
        -- TCO = bruto + patronale kost
        (
            c.bruto
            + coalesce(public.cascade_stap2_basis_patronale_rsz(c.bruto, c.status, c.werkgeverscategorie, p_periode), 0)
            - coalesce(public.cascade_stap3_structurele_vermindering(c.bruto * 3, 1.0000, c.werkgeverscategorie, p_periode), 0)
            + coalesce(public.cascade_stap5_bijzondere_bijdragen(c.bruto, p_periode), 0)
            + coalesce(public.cascade_stap6_vakantiegeld(c.bruto, c.status, p_periode), 0)
        )::numeric(18, 4) as tco
    from contracten c;
$$;

comment on function public.cascade_populatie_snapshot(date, uuid, uuid) is
    'Populatie-snapshot: alle contracten in tenant + cascade output. RLS filtert via dim_contract / dim_legale_entiteit tenant-scoping.';

grant execute on function public.cascade_populatie_snapshot(date, uuid, uuid) to authenticated;
