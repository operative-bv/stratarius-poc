-- ================================================================
-- T-057: create_scenario_with_mutations — unified scenario mutator
-- ================================================================
--
-- Combineert loon-mutatie + wagen-add + extralegaal in één RPC via jsonb array.
-- Bestaande create_what_if_scenario en create_wagen_scenario blijven staan
-- voor backward-compat en simpelere UI paths.
--
-- Mutation schema:
--   [
--     { "type": "loon_pct_increase",  "value": 5.0,  "filter": {...T-056 filter...} },
--     { "type": "loon_flat_replace",  "value": 4000, "filter": {...} },
--     { "type": "wagen_add",          "wagen_categorie": "electric|compact|mid|premium",
--                                     "filter": {...} }
--   ]
--
-- Filter herbruikt T-056 schema: pc_ids/statussen/functie_ids (subset).
-- Empty filter = alle contracten in legale_entiteit.
--
-- POC-scope: 3 mutation types. Uitbreiding (extralegaal_add, contract_status_change,
-- wagen_swap) is aparte follow-up.
--
-- Idempotency: elke call maakt een NIEUW scenario (nieuwe UUID). Herhaalde call
-- levert dus 2 aparte scenarios op — geen ON CONFLICT logic.
--
-- Rollback:
--   DROP FUNCTION public.create_scenario_with_mutations(uuid, text, uuid, date, jsonb);


create or replace function public.create_scenario_with_mutations(
    p_legale_entiteit_id   uuid,
    p_naam                 text,
    p_baseline_scenario_id uuid,
    p_periode              date,
    p_mutations            jsonb
)
    returns uuid
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_scenario_id uuid := gen_random_uuid();
    v_mutation jsonb;
    v_type text;
    v_filter jsonb;
    v_wagen_categorie text;
    v_cataloguswaarde numeric(18, 4);
    v_lease_maand numeric(18, 4);
begin
    -- Input validation
    if p_naam is null or length(trim(p_naam)) = 0 then
        raise exception 'scenario naam is verplicht' using errcode = '22023';
    end if;
    if jsonb_typeof(p_mutations) <> 'array' or jsonb_array_length(p_mutations) = 0 then
        raise exception 'mutations moet een niet-lege jsonb array zijn' using errcode = '22023';
    end if;

    -- Pre-scan: validate all mutation types before creating scenario
    for v_mutation in select jsonb_array_elements(p_mutations) loop
        v_type := v_mutation ->> 'type';
        if v_type not in ('loon_pct_increase', 'loon_flat_replace', 'wagen_add') then
            raise exception 'onbekende mutation type: % (verwacht loon_pct_increase|loon_flat_replace|wagen_add)', v_type using errcode = '22023';
        end if;
        if v_type = 'wagen_add' then
            v_wagen_categorie := v_mutation ->> 'wagen_categorie';
            if v_wagen_categorie not in ('compact', 'mid', 'premium', 'electric') then
                raise exception 'wagen_categorie moet zijn compact|mid|premium|electric, gekregen: %', v_wagen_categorie using errcode = '22023';
            end if;
        end if;
    end loop;

    -- Create nieuw scenario met snapshot ref (T-054)
    insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind, param_snapshot_batch_id)
    values (v_scenario_id, p_legale_entiteit_id, p_naam, 'what_if', public.get_current_snapshot_batch_id());

    -- Copy baseline fact_looncomponent (unchanged) naar nieuw scenario_id
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select contract_id, periode, component_id, v_scenario_id, bedrag,
           'copy_baseline_' || v_scenario_id::text
    from public.fact_looncomponent
    where scenario_id = p_baseline_scenario_id
      and periode = p_periode;

    -- Apply elke mutation in volgorde
    for v_mutation in select jsonb_array_elements(p_mutations) loop
        v_type := v_mutation ->> 'type';
        v_filter := coalesce(v_mutation -> 'filter', '{}'::jsonb);

        if v_type = 'loon_pct_increase' then
            update public.fact_looncomponent fl
            set bedrag = (fl.bedrag * (1 + (v_mutation ->> 'value')::numeric / 100))::numeric(18, 4)
            from public.dim_looncomponent dl
            where dl.component_id = fl.component_id
              and dl.is_basisloon
              and fl.scenario_id = v_scenario_id
              and fl.periode = p_periode
              and fl.contract_id in (
                  select c.contract_id
                  from public.dim_contract c
                  where c.legale_entiteit_id = p_legale_entiteit_id
                    and c.geldig_van <= p_periode
                    and (c.geldig_tot is null or c.geldig_tot > p_periode)
                    and (not (v_filter ? 'functie_ids')
                         or c.functie_id = any (array(select (jsonb_array_elements_text(v_filter -> 'functie_ids'))::uuid)))
                    and (not (v_filter ? 'pc_ids')
                         or c.pc_id = any (array(select jsonb_array_elements_text(v_filter -> 'pc_ids'))))
                    and (not (v_filter ? 'statussen')
                         or c.status = any (array(select jsonb_array_elements_text(v_filter -> 'statussen'))))
              );

        elsif v_type = 'loon_flat_replace' then
            update public.fact_looncomponent fl
            set bedrag = (v_mutation ->> 'value')::numeric(18, 4)
            from public.dim_looncomponent dl
            where dl.component_id = fl.component_id
              and dl.is_basisloon
              and fl.scenario_id = v_scenario_id
              and fl.periode = p_periode
              and fl.contract_id in (
                  select c.contract_id
                  from public.dim_contract c
                  where c.legale_entiteit_id = p_legale_entiteit_id
                    and c.geldig_van <= p_periode
                    and (c.geldig_tot is null or c.geldig_tot > p_periode)
                    and (not (v_filter ? 'functie_ids')
                         or c.functie_id = any (array(select (jsonb_array_elements_text(v_filter -> 'functie_ids'))::uuid)))
                    and (not (v_filter ? 'pc_ids')
                         or c.pc_id = any (array(select jsonb_array_elements_text(v_filter -> 'pc_ids'))))
                    and (not (v_filter ? 'statussen')
                         or c.status = any (array(select jsonb_array_elements_text(v_filter -> 'statussen'))))
              );

        elsif v_type = 'wagen_add' then
            v_wagen_categorie := v_mutation ->> 'wagen_categorie';
            -- Wagen categorie mapping (POC-simplified, matches create_wagen_scenario)
            case v_wagen_categorie
                when 'compact'  then v_cataloguswaarde := 25000; v_lease_maand := 450;
                when 'mid'      then v_cataloguswaarde := 38000; v_lease_maand := 650;
                when 'premium'  then v_cataloguswaarde := 55000; v_lease_maand := 900;
                when 'electric' then v_cataloguswaarde := 45000; v_lease_maand := 700;
            end case;

            -- Insert bedrijfswagen_tco (lease-kost werkgever) voor filtered contracten
            insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
            select c.contract_id, p_periode, 'bedrijfswagen_tco', v_scenario_id, v_lease_maand,
                   'wagen_add_' || v_wagen_categorie
            from public.dim_contract c
            where c.legale_entiteit_id = p_legale_entiteit_id
              and c.geldig_van <= p_periode
              and (c.geldig_tot is null or c.geldig_tot > p_periode)
              and (not (v_filter ? 'functie_ids')
                   or c.functie_id = any (array(select (jsonb_array_elements_text(v_filter -> 'functie_ids'))::uuid)))
              and (not (v_filter ? 'pc_ids')
                   or c.pc_id = any (array(select jsonb_array_elements_text(v_filter -> 'pc_ids'))))
              and (not (v_filter ? 'statussen')
                   or c.status = any (array(select jsonb_array_elements_text(v_filter -> 'statussen'))))
            on conflict (contract_id, periode, component_id, scenario_id) do update
            set bedrag = excluded.bedrag,
                bron_ref = excluded.bron_ref,
                updated_at = now();

            -- Insert bedrijfswagen_vaa (fiscaal voordeel werknemer, schaduw-bedrag)
            insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
            select c.contract_id, p_periode, 'bedrijfswagen_vaa', v_scenario_id,
                   (v_cataloguswaarde * 0.06 / 12)::numeric(18, 4),
                   'wagen_add_' || v_wagen_categorie
            from public.dim_contract c
            where c.legale_entiteit_id = p_legale_entiteit_id
              and c.geldig_van <= p_periode
              and (c.geldig_tot is null or c.geldig_tot > p_periode)
              and (not (v_filter ? 'functie_ids')
                   or c.functie_id = any (array(select (jsonb_array_elements_text(v_filter -> 'functie_ids'))::uuid)))
              and (not (v_filter ? 'pc_ids')
                   or c.pc_id = any (array(select jsonb_array_elements_text(v_filter -> 'pc_ids'))))
              and (not (v_filter ? 'statussen')
                   or c.status = any (array(select jsonb_array_elements_text(v_filter -> 'statussen'))))
            on conflict (contract_id, periode, component_id, scenario_id) do update
            set bedrag = excluded.bedrag,
                bron_ref = excluded.bron_ref,
                updated_at = now();
        end if;
    end loop;

    return v_scenario_id;
end;
$$;

comment on function public.create_scenario_with_mutations(uuid, text, uuid, date, jsonb) is
    'Unified scenario mutator: combineert loon_pct_increase, loon_flat_replace, en wagen_add mutations in één RPC. Elke mutation heeft optionele filter (T-056 schema pc_ids/statussen/functie_ids). Pre-scan valideert types voor scenario-creatie. Auto-populates dim_scenario.param_snapshot_batch_id via T-054 helper. Bestaande create_what_if_scenario en create_wagen_scenario blijven voor backward-compat.';

grant execute on function public.create_scenario_with_mutations(uuid, text, uuid, date, jsonb) to authenticated;
