-- Scenario editor RPC: create nieuw scenario + kopieer baseline fact_looncomponent met mutatie
--
-- Mutatie types:
--   'pct_increase'   : bedrag * (1 + p_mutatie_value/100)
--   'flat_increase'  : bedrag + p_mutatie_value
--   'flat_replace'   : bedrag = p_mutatie_value (voor basisloon overrides)
--
-- Filter: optional p_functie_id — mutatie geldt alleen voor contracten in dat team,
-- anderen krijgen baseline waarden gekopieerd.

create or replace function public.create_what_if_scenario(
    p_legale_entiteit_id uuid,
    p_naam text,
    p_baseline_scenario_id uuid,
    p_periode date,
    p_mutatie_type text,
    p_mutatie_value numeric,
    p_functie_id uuid default null
)
    returns uuid
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_scenario_id uuid;
    v_rows_created int;
begin
    if auth.uid() is null then
        raise exception 'authenticated caller required' using errcode = '42501';
    end if;
    if p_naam is null or length(trim(p_naam)) = 0 then
        raise exception 'scenario naam is verplicht' using errcode = '22023';
    end if;
    if p_mutatie_type not in ('pct_increase', 'flat_increase', 'flat_replace') then
        raise exception 'mutatie_type moet zijn: pct_increase | flat_increase | flat_replace' using errcode = '22023';
    end if;

    v_scenario_id := gen_random_uuid();

    -- Create nieuw scenario
    insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind)
    values (v_scenario_id, p_legale_entiteit_id, p_naam, 'what_if');

    -- Kopieer fact_looncomponent onder nieuw scenario met mutatie op basisloon
    -- voor contracten in scope (functie filter). Andere componenten worden 1:1 gekopieerd.
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select
        fl.contract_id,
        fl.periode,
        fl.component_id,
        v_scenario_id,
        case
            when dl.is_basisloon
                 and (p_functie_id is null or c.functie_id = p_functie_id)
            then
                case p_mutatie_type
                    when 'pct_increase'  then (fl.bedrag * (1 + p_mutatie_value / 100))::numeric(18, 4)
                    when 'flat_increase' then (fl.bedrag + p_mutatie_value)::numeric(18, 4)
                    when 'flat_replace'  then p_mutatie_value::numeric(18, 4)
                end
            else fl.bedrag
        end as bedrag,
        'scenario_' || v_scenario_id::text
    from public.fact_looncomponent fl
    join public.dim_looncomponent dl on dl.component_id = fl.component_id
    join public.dim_contract c on c.contract_id = fl.contract_id
    where fl.scenario_id = p_baseline_scenario_id
      and fl.periode = p_periode;

    get diagnostics v_rows_created = row_count;

    return v_scenario_id;
end;
$$;

comment on function public.create_what_if_scenario(uuid, text, uuid, date, text, numeric, uuid) is
    'Create what-if scenario door fact_looncomponent kopie van baseline met mutatie op basisloon. Mutatie types: pct_increase, flat_increase, flat_replace. Optioneel gefilterd per functie_id.';

grant execute on function public.create_what_if_scenario(uuid, text, uuid, date, text, numeric, uuid) to authenticated;
