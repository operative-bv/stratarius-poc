-- T-028: cascade_stap7_extralegaal taks-som
create or replace function public.cascade_stap7_extralegaal(
    p_contract_id uuid,
    p_periode     date,
    p_scenario_id uuid
)
    returns numeric(18, 4)
    language sql stable parallel safe
    set search_path = public, pg_temp
as $$
    select coalesce(sum(fl.bedrag * pe.taks_pct), 0)::numeric(18, 4)
    from public.fact_looncomponent fl
    join public.dim_looncomponent dl on dl.component_id = fl.component_id
    join public.param_extralegaal pe on pe.voordeeltype = dl.component_id
    where fl.contract_id = p_contract_id
      and fl.periode = p_periode
      and fl.scenario_id = p_scenario_id
      and dl.familie = 'extralegaal'
      and p_periode >= pe.geldig_van
      and (pe.geldig_tot is null or p_periode < pe.geldig_tot);
$$;

comment on function public.cascade_stap7_extralegaal(uuid, date, uuid) is
    'Cascade stap 7: som van extralegaal-componenten × taks_pct via voordeeltype JOIN. Naming mismatch (dim_looncomponent maaltijdcheques vs param_extralegaal maaltijdcheque) → alleen exact matches. Groepsverzekering (13.26%) is de belangrijkste taks-drager voor POC.';

grant execute on function public.cascade_stap7_extralegaal(uuid, date, uuid) to authenticated;
