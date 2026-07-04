-- Wagen scenario RPC: create scenario met wagen-toewijzing per team
-- Voor elk contract in scope: insert fact_wagen + fact_looncomponent
-- (bedrijfswagen_tco = maandelijkse leasekost patronaal, wordt niet gefilterd door
-- rsz_plichtig want stap 8 buiten POC).
--
-- Wagen categorien (POC vereenvoudigd):
--   compact   : cataloguswaarde 25000, lease 450/maand, CO2 105
--   mid       : cataloguswaarde 38000, lease 650/maand, CO2 130
--   premium   : cataloguswaarde 55000, lease 900/maand, CO2 155
--   electric  : cataloguswaarde 45000, lease 700/maand, CO2 0

create or replace function public.create_wagen_scenario(
    p_legale_entiteit_id uuid,
    p_naam text,
    p_baseline_scenario_id uuid,
    p_periode date,
    p_functie_id uuid,
    p_wagen_categorie text
)
    returns uuid
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_scenario_id uuid;
    v_cataloguswaarde numeric(18, 4);
    v_lease_maand numeric(18, 4);
    v_co2 int;
    v_brandstof text;
begin
    if auth.uid() is null then
        raise exception 'authenticated caller required' using errcode = '42501';
    end if;
    if p_functie_id is null then
        raise exception 'p_functie_id is verplicht (team scope)' using errcode = '22023';
    end if;

    -- Categorie mapping
    case p_wagen_categorie
        when 'compact'  then v_cataloguswaarde := 25000; v_lease_maand := 450; v_co2 := 105; v_brandstof := 'diesel';
        when 'mid'      then v_cataloguswaarde := 38000; v_lease_maand := 650; v_co2 := 130; v_brandstof := 'diesel';
        when 'premium'  then v_cataloguswaarde := 55000; v_lease_maand := 900; v_co2 := 155; v_brandstof := 'diesel';
        when 'electric' then v_cataloguswaarde := 45000; v_lease_maand := 700; v_co2 := 0;   v_brandstof := 'elektrisch';
        else raise exception 'p_wagen_categorie moet zijn: compact | mid | premium | electric' using errcode = '22023';
    end case;

    v_scenario_id := gen_random_uuid();

    insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind)
    values (v_scenario_id, p_legale_entiteit_id, p_naam, 'what_if');

    -- Kopieer baseline fact_looncomponent + voeg bedrijfswagen_tco toe
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select fl.contract_id, fl.periode, fl.component_id, v_scenario_id, fl.bedrag, 'copy_baseline'
    from public.fact_looncomponent fl
    where fl.scenario_id = p_baseline_scenario_id and fl.periode = p_periode;

    -- Voeg wagen-lease kost toe voor contracten in scope (team)
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select c.contract_id, p_periode, 'bedrijfswagen_tco', v_scenario_id, v_lease_maand,
           'wagen_scenario_' || p_wagen_categorie
    from public.dim_contract c
    where c.functie_id = p_functie_id
      and c.geldig_van <= p_periode
      and (c.geldig_tot is null or c.geldig_tot > p_periode);

    -- Voeg wagen-VAA toe (fiscaal voordeel voor werknemer, geen patronale kost maar wel schaduw)
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select c.contract_id, p_periode, 'bedrijfswagen_vaa', v_scenario_id,
           -- POC VAA: cataloguswaarde × 6/7 × leeftijdscoefficient × CO2-coefficient (simplified)
           (v_cataloguswaarde * 0.06 / 12)::numeric(18, 4),
           'wagen_scenario_' || p_wagen_categorie
    from public.dim_contract c
    where c.functie_id = p_functie_id
      and c.geldig_van <= p_periode
      and (c.geldig_tot is null or c.geldig_tot > p_periode);

    return v_scenario_id;
end;
$$;

comment on function public.create_wagen_scenario(uuid, text, uuid, date, uuid, text) is
    'Create wagen-scenario voor team: kopieer baseline + voeg bedrijfswagen_tco (lease) + VAA per contract in team scope toe.';

grant execute on function public.create_wagen_scenario(uuid, text, uuid, date, uuid, text) to authenticated;
