-- ================================================================
-- ISS-088: Scenario-RPCs — tenant validation
-- ================================================================
--
-- create_what_if_scenario, create_wagen_scenario en
-- create_scenario_with_mutations waren SECURITY DEFINER zonder
-- has_role_on_account check. Codex-review C1 (Claude miste dit):
-- auth'd user van tenant A kon scenario aan tenant B koppelen én
-- tenant B's baseline-data kopiëren via p_baseline_scenario_id.
--
-- Pattern: cascade_populatie_snapshot (commit 3343d8f):
-- 1. auth.uid() check
-- 2. Lookup owning_account_id via dim_legale_entiteit
-- 3. has_role_on_account(owning_account_id) check
-- 4. Als p_baseline_scenario_id opgegeven: verifieer dat baseline
--    tot DEZELFDE tenant behoort (niet alleen "any tenant caller
--    has access to").
--
-- Extra fix in create_wagen_scenario: where-clause op dim_contract
-- checkte alleen c.functie_id en niet c.legale_entiteit_id, dus als
-- p_functie_id van tenant B kwam kon je tenant B contracten wagen-
-- assigneren onder tenant A's scenario. Toegevoegd:
--   and c.legale_entiteit_id = p_legale_entiteit_id
-- ================================================================


-- ================================================================
-- 1. create_what_if_scenario — tenant checks
-- ================================================================

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
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_baseline_account uuid;
    v_scenario_id uuid;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'create_what_if_scenario: authenticated caller required'
            using errcode = '42501';
    end if;

    -- Tenant check op legale entiteit
    select owning_account_id into v_owning_account
    from public.dim_legale_entiteit
    where legale_entiteit_id = p_legale_entiteit_id;
    if v_owning_account is null then
        raise exception 'create_what_if_scenario: entiteit % niet gevonden', p_legale_entiteit_id
            using errcode = '02000';
    end if;
    if not basejump.has_role_on_account(v_owning_account) then
        raise exception 'create_what_if_scenario: geen toegang tot entiteit %', p_legale_entiteit_id
            using errcode = '42501';
    end if;

    -- Baseline scenario moet tot dezelfde tenant behoren
    select le.owning_account_id into v_baseline_account
    from public.dim_scenario s
    join public.dim_legale_entiteit le on le.legale_entiteit_id = s.legale_entiteit_id
    where s.scenario_id = p_baseline_scenario_id;
    if v_baseline_account is null then
        raise exception 'create_what_if_scenario: baseline scenario % niet gevonden', p_baseline_scenario_id
            using errcode = '02000';
    end if;
    if v_baseline_account <> v_owning_account then
        raise exception 'create_what_if_scenario: baseline scenario % behoort niet tot tenant', p_baseline_scenario_id
            using errcode = '42501';
    end if;

    -- Input validation (blijft ongewijzigd)
    if p_naam is null or length(trim(p_naam)) = 0 then
        raise exception 'scenario naam is verplicht' using errcode = '22023';
    end if;
    if p_mutatie_type not in ('pct_increase', 'flat_increase', 'flat_replace') then
        raise exception 'mutatie_type moet zijn: pct_increase | flat_increase | flat_replace' using errcode = '22023';
    end if;

    v_scenario_id := gen_random_uuid();

    insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind)
    values (v_scenario_id, p_legale_entiteit_id, p_naam, 'what_if');

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
      and fl.periode = p_periode
      and c.legale_entiteit_id = p_legale_entiteit_id;

    return v_scenario_id;
end;
$$;


-- ================================================================
-- 2. create_wagen_scenario — tenant checks + entiteit filter fix
-- ================================================================

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
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_baseline_account uuid;
    v_scenario_id uuid;
    v_cataloguswaarde numeric(18, 4);
    v_lease_maand numeric(18, 4);
    v_co2 int;
    v_brandstof text;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'create_wagen_scenario: authenticated caller required'
            using errcode = '42501';
    end if;

    select owning_account_id into v_owning_account
    from public.dim_legale_entiteit
    where legale_entiteit_id = p_legale_entiteit_id;
    if v_owning_account is null then
        raise exception 'create_wagen_scenario: entiteit % niet gevonden', p_legale_entiteit_id
            using errcode = '02000';
    end if;
    if not basejump.has_role_on_account(v_owning_account) then
        raise exception 'create_wagen_scenario: geen toegang tot entiteit %', p_legale_entiteit_id
            using errcode = '42501';
    end if;

    select le.owning_account_id into v_baseline_account
    from public.dim_scenario s
    join public.dim_legale_entiteit le on le.legale_entiteit_id = s.legale_entiteit_id
    where s.scenario_id = p_baseline_scenario_id;
    if v_baseline_account is null then
        raise exception 'create_wagen_scenario: baseline scenario % niet gevonden', p_baseline_scenario_id
            using errcode = '02000';
    end if;
    if v_baseline_account <> v_owning_account then
        raise exception 'create_wagen_scenario: baseline scenario % behoort niet tot tenant', p_baseline_scenario_id
            using errcode = '42501';
    end if;

    if p_functie_id is null then
        raise exception 'p_functie_id is verplicht (team scope)' using errcode = '22023';
    end if;

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

    -- Kopieer baseline — restrict to entiteit-owned contracten
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select fl.contract_id, fl.periode, fl.component_id, v_scenario_id, fl.bedrag, 'copy_baseline'
    from public.fact_looncomponent fl
    join public.dim_contract c on c.contract_id = fl.contract_id
    where fl.scenario_id = p_baseline_scenario_id
      and fl.periode = p_periode
      and c.legale_entiteit_id = p_legale_entiteit_id;

    -- Wagen-lease: nu OOK filter op c.legale_entiteit_id (was gap)
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select c.contract_id, p_periode, 'bedrijfswagen_tco', v_scenario_id, v_lease_maand,
           'wagen_scenario_' || p_wagen_categorie
    from public.dim_contract c
    where c.functie_id = p_functie_id
      and c.legale_entiteit_id = p_legale_entiteit_id
      and c.geldig_van <= p_periode
      and (c.geldig_tot is null or c.geldig_tot > p_periode);

    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select c.contract_id, p_periode, 'bedrijfswagen_vaa', v_scenario_id,
           (v_cataloguswaarde * 0.06 / 12)::numeric(18, 4),
           'wagen_scenario_' || p_wagen_categorie
    from public.dim_contract c
    where c.functie_id = p_functie_id
      and c.legale_entiteit_id = p_legale_entiteit_id
      and c.geldig_van <= p_periode
      and (c.geldig_tot is null or c.geldig_tot > p_periode);

    return v_scenario_id;
end;
$$;


-- ================================================================
-- 3. create_scenario_with_mutations — tenant checks
-- ================================================================

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
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_baseline_account uuid;
    v_scenario_id uuid := gen_random_uuid();
    v_mutation jsonb;
    v_type text;
    v_filter jsonb;
    v_wagen_categorie text;
    v_cataloguswaarde numeric(18, 4);
    v_lease_maand numeric(18, 4);
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'create_scenario_with_mutations: authenticated caller required'
            using errcode = '42501';
    end if;

    select owning_account_id into v_owning_account
    from public.dim_legale_entiteit
    where legale_entiteit_id = p_legale_entiteit_id;
    if v_owning_account is null then
        raise exception 'create_scenario_with_mutations: entiteit % niet gevonden', p_legale_entiteit_id
            using errcode = '02000';
    end if;
    if not basejump.has_role_on_account(v_owning_account) then
        raise exception 'create_scenario_with_mutations: geen toegang tot entiteit %', p_legale_entiteit_id
            using errcode = '42501';
    end if;

    select le.owning_account_id into v_baseline_account
    from public.dim_scenario s
    join public.dim_legale_entiteit le on le.legale_entiteit_id = s.legale_entiteit_id
    where s.scenario_id = p_baseline_scenario_id;
    if v_baseline_account is null then
        raise exception 'create_scenario_with_mutations: baseline scenario % niet gevonden', p_baseline_scenario_id
            using errcode = '02000';
    end if;
    if v_baseline_account <> v_owning_account then
        raise exception 'create_scenario_with_mutations: baseline scenario % behoort niet tot tenant', p_baseline_scenario_id
            using errcode = '42501';
    end if;

    -- Input validation
    if p_naam is null or length(trim(p_naam)) = 0 then
        raise exception 'scenario naam is verplicht' using errcode = '22023';
    end if;
    if jsonb_typeof(p_mutations) <> 'array' or jsonb_array_length(p_mutations) = 0 then
        raise exception 'mutations moet een niet-lege jsonb array zijn' using errcode = '22023';
    end if;

    -- Pre-scan
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

    insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind, param_snapshot_batch_id)
    values (v_scenario_id, p_legale_entiteit_id, p_naam, 'what_if', public.get_current_snapshot_batch_id());

    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    select fl.contract_id, fl.periode, fl.component_id, v_scenario_id, fl.bedrag,
           'copy_baseline_' || v_scenario_id::text
    from public.fact_looncomponent fl
    join public.dim_contract c on c.contract_id = fl.contract_id
    where fl.scenario_id = p_baseline_scenario_id
      and fl.periode = p_periode
      and c.legale_entiteit_id = p_legale_entiteit_id;

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
            case v_wagen_categorie
                when 'compact'  then v_cataloguswaarde := 25000; v_lease_maand := 450;
                when 'mid'      then v_cataloguswaarde := 38000; v_lease_maand := 650;
                when 'premium'  then v_cataloguswaarde := 55000; v_lease_maand := 900;
                when 'electric' then v_cataloguswaarde := 45000; v_lease_maand := 700;
            end case;

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


comment on function public.create_what_if_scenario(uuid, text, uuid, date, text, numeric, uuid) is
    'Create what-if scenario door fact_looncomponent kopie van baseline met mutatie op basisloon. '
    'ISS-088: tenant validation via has_role_on_account + baseline-scenario tenant-match check. '
    'Mutatie types: pct_increase, flat_increase, flat_replace. Optioneel gefilterd per functie_id.';

comment on function public.create_wagen_scenario(uuid, text, uuid, date, uuid, text) is
    'Create wagen-scenario voor team: kopieer baseline + voeg bedrijfswagen_tco (lease) + VAA per contract in team scope toe. '
    'ISS-088: tenant validation via has_role_on_account + baseline-scenario tenant-match + expliciete '
    'c.legale_entiteit_id filter (was cross-tenant hazard).';

comment on function public.create_scenario_with_mutations(uuid, text, uuid, date, jsonb) is
    'Unified scenario mutator: combineert loon_pct_increase, loon_flat_replace, en wagen_add mutations in één RPC. '
    'ISS-088: tenant validation via has_role_on_account + baseline-scenario tenant-match check. '
    'Elke mutation heeft optionele filter (T-056 schema pc_ids/statussen/functie_ids). Pre-scan valideert types voor scenario-creatie. '
    'Auto-populates dim_scenario.param_snapshot_batch_id via T-054 helper.';
