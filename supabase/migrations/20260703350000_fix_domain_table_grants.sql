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

-- Parameter tables (public reference, RLS = read to authenticated)
grant select on public.param_rsz to authenticated;
grant select on public.param_structurele_vermindering to authenticated;
grant select on public.param_doelgroepvermindering to authenticated;
grant select on public.param_arbeidsduur to authenticated;
grant select on public.param_vakantiegeld to authenticated;
grant select on public.param_bijzondere_bijdragen to authenticated;
grant select on public.param_sectorbijdrage to authenticated;
grant select on public.param_extralegaal to authenticated;
grant select on public.param_wagen_mobiliteit to authenticated;
grant select on public.param_index to authenticated;
grant select on public.param_plafond to authenticated;

-- Overige tabellen
grant select on public.dim_persoon_arbeidsverleden to authenticated;
grant select on public.gdpr_access_log to authenticated;
grant select on public.mart_loonkloof to authenticated;
grant select on public.bridge_hierarchie to authenticated;
grant select on public.dim_hierarchie to authenticated;
grant select on public.dim_org_unit to authenticated;
grant select on public.map_entiteit_pc_competentie to authenticated;

-- Insert/update op fact tables (voor simulator scenarios)
grant insert on public.fact_looncomponent to authenticated;
grant insert on public.fact_prestatie to authenticated;
grant insert on public.dim_scenario to authenticated;
