-- Fix: RLS policies bestaan maar table-level SELECT grants ontbreken voor authenticated.
-- Zonder deze grants faalt elke SELECT met "permission denied for table X" ongeacht RLS.

grant select on public.dim_persoon to authenticated;
grant select on public.dim_contract to authenticated;
grant select on public.dim_functie to authenticated;
grant select on public.dim_legale_entiteit to authenticated;
grant select on public.dim_land to authenticated;
grant select on public.dim_scenario to authenticated;
grant select on public.dim_looncomponent to authenticated;
grant select on public.dim_prestatiecode to authenticated;
grant select on public.dim_sz_behandeling to authenticated;
grant select on public.dim_pc to authenticated;
grant select on public.fact_looncomponent to authenticated;
grant select on public.fact_prestatie to authenticated;
grant select on public.fact_wagen to authenticated;
grant select on public.fact_loonkost to authenticated;

-- Insert/update op fact tables (voor simulator scenarios)
grant insert on public.fact_looncomponent to authenticated;
grant insert on public.fact_prestatie to authenticated;
grant insert on public.dim_scenario to authenticated;
