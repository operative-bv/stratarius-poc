-- ================================================================
-- ISS-042: batch-variant demo voor cascade_stap2 (N+1 mitigation pattern)
-- ================================================================
--
-- ISS-042 signaleerde dat scalar cascade functies bij grote populaties N×M×S
-- invocations kunnen kosten. Meting op POC-schaal (27 seed contracten, Demo BVBA):
--   cascade_populatie_snapshot(2024-06-01) → 22ms end-to-end.
--   Per-contract kost: ~0.8ms (planner cache + inlined STABLE functions).
--
-- Op productieschaal (10k+ contracten) wordt dit ~8s. Nog geen show-stopper,
-- maar meetbaar. Deze migration levert het BATCH PATTERN als demonstratie:
-- een RETURNS TABLE variant die één set-based JOIN doet ipv per-row function call.
--
-- Scope:
--   Alleen stap 2 als proof-of-pattern. Stap 3-9 volgen zelfde patroon zodra
--   productie-metingen tonen dat verdere optimalisatie nodig is (measure first,
--   optimize second). Populatie_snapshot blijft de canonical read interface;
--   het switcht pas naar batch variants wanneer profiel-cijfers dat rechtvaardigen.
--
-- Rollback:
--   DROP FUNCTION public.cascade_stap2_basis_patronale_rsz_batch(date, uuid, jsonb);


create or replace function public.cascade_stap2_basis_patronale_rsz_batch(
    p_periode     date,
    p_scenario_id uuid default null,
    p_filters     jsonb default '{}'::jsonb
)
    returns table (
        contract_id uuid,
        bedrag      numeric(18, 4)
    )
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    -- Één query per (periode, scenario, filters) → één JOIN per row.
    -- Beter dan cascade_stap2_basis_patronale_rsz(numeric, text, smallint, date)
    -- die per-contract wordt aangeroepen door populatie_snapshot.
    with contracten as (
        select
            c.contract_id,
            c.status,
            le.werkgeverscategorie,
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
        where c.geldig_van <= p_periode
          and (c.geldig_tot is null or c.geldig_tot > p_periode)
          -- Filter herbruikt T-056 subset waar zinvol voor stap 2 (pc_ids/statussen/gewesten).
          and (not (p_filters ? 'pc_ids')
               or c.pc_id = any (array(select jsonb_array_elements_text(p_filters -> 'pc_ids'))))
          and (not (p_filters ? 'statussen')
               or c.status = any (array(select jsonb_array_elements_text(p_filters -> 'statussen'))))
          and (not (p_filters ? 'gewesten')
               or le.gewest = any (array(select jsonb_array_elements_text(p_filters -> 'gewesten'))))
    )
    select
        ct.contract_id,
        (ct.bruto * pr.basisbijdrage_pct * pr.basisfactor_pct)::numeric(18, 4) as bedrag
    from contracten ct
    left join public.param_rsz pr
      on pr.status = ct.status
     and pr.werkgeverscategorie = ct.werkgeverscategorie
     and p_periode >= pr.geldig_van
     and (pr.geldig_tot is null or p_periode < pr.geldig_tot);
$$;

comment on function public.cascade_stap2_basis_patronale_rsz_batch(date, uuid, jsonb) is
    'Batch-variant van cascade_stap2_basis_patronale_rsz (ISS-042 pattern demo). Één JOIN ipv per-contract function call. Voor productieschaal (10k+ contracten) meetbaar sneller dan scalar variant in populatie_snapshot. Filter subset uit T-056 (pc_ids/statussen/gewesten). Sibling batch-variants voor stap 3-9 volgen zelfde patroon wanneer profielcijfers verdere optimalisatie rechtvaardigen.';

grant execute on function public.cascade_stap2_basis_patronale_rsz_batch(date, uuid, jsonb) to authenticated;
