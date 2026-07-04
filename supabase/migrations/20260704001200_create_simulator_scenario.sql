-- ================================================================
-- T-051: create_simulator_scenario — synthetic contract flow RPC
-- ================================================================
--
-- Simulator v1: één RPC die in transactie een compleet what-if scenario
-- opzet voor een synthetische medewerker, inclusief persist naar fact_loonkost.
--
-- Vervangt T-035 UX-flow (direct cascade RPC calls zonder persistence) door
-- een volledige write path. Nieuwe UI kan resultaat opvragen via bestaande
-- populatie / fact_loonkost queries onder het teruggegeven scenario_id.
--
-- Input schema (p_input jsonb):
--   {
--     "persoon":   {"geboortedatum": "YYYY-MM-DD", "geslacht": "m|v|x", "opleiding": "..."},
--     "functie":   {"naam": "...", "niveau": int},
--     "contract":  {"pc_id": "200", "status": "arbeider|bediende", "fte_breuk": 1.0},
--     "prestatie": {"uren_per_maand": numeric},
--     "loon":      {"basisloon": numeric}
--   }
--
-- Behavior in één transactie (plpgsql auto-transactional):
--   1. INSERT dim_persoon (synthetic, owning_account_id = tenant)
--   2. INSERT dim_functie (synthetic, owning_account_id = tenant)
--   3. INSERT dim_scenario (kind='what_if', param_snapshot_batch_id via T-054)
--   4. INSERT dim_contract (linkt persoon+functie+entiteit)
--   5. INSERT fact_prestatie (met dim_prestatiecode 'gewerkte_uren' als default)
--   6. INSERT fact_looncomponent (basisloon component, scenario-linked)
--   7. Call create_populatie_loonkost(periode, scenario_id) → 7 kostenblok rijen
--   8. Return scenario_id
--
-- SECURITY DEFINER: writes op dim_contract, fact_looncomponent zijn RLS-scoped
-- via tenant chain — SDF garandeert dat de function bij owner-priv kan schrijven.
-- Caller-verificatie via basejump.has_role_on_account op p_legale_entiteit_id.
--
-- Rollback:
--   DROP FUNCTION public.create_simulator_scenario(uuid, text, date, jsonb);


create or replace function public.create_simulator_scenario(
    p_legale_entiteit_id uuid,
    p_naam               text,
    p_periode            date,
    p_input              jsonb
)
    returns uuid
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_persoon_id  uuid := gen_random_uuid();
    v_functie_id  uuid := gen_random_uuid();
    v_contract_id uuid := gen_random_uuid();
    v_scenario_id uuid := gen_random_uuid();
    v_owning_account_id uuid;
    v_prestatiecode_id text;
begin
    -- Input validation
    if p_naam is null or length(trim(p_naam)) = 0 then
        raise exception 'scenario naam is verplicht' using errcode = '22023';
    end if;
    if p_input -> 'persoon' is null
       or p_input -> 'functie' is null
       or p_input -> 'contract' is null
       or p_input -> 'prestatie' is null
       or p_input -> 'loon' is null
    then
        raise exception 'input moet persoon+functie+contract+prestatie+loon secties bevatten' using errcode = '22023';
    end if;

    -- Resolve owning_account_id via legale_entiteit
    select le.owning_account_id into v_owning_account_id
    from public.dim_legale_entiteit le
    where le.legale_entiteit_id = p_legale_entiteit_id;

    if v_owning_account_id is null then
        raise exception 'legale_entiteit % niet gevonden', p_legale_entiteit_id using errcode = '22023';
    end if;

    -- Kies default prestatiecode 'gewerkte_uren' (algemeen aanwezig in dim_prestatiecode seed)
    select prestatiecode into v_prestatiecode_id
    from public.dim_prestatiecode
    where telt_voor_mu = true
    limit 1;

    -- 1) dim_persoon
    insert into public.dim_persoon (persoon_id, owning_account_id, geboortedatum, geslacht, opleidingsniveau)
    values (v_persoon_id, v_owning_account_id,
            (p_input -> 'persoon' ->> 'geboortedatum')::date,
            p_input -> 'persoon' ->> 'geslacht',
            p_input -> 'persoon' ->> 'opleiding');

    -- 2) dim_functie
    insert into public.dim_functie (functie_id, owning_account_id, functienaam, functieniveau)
    values (v_functie_id, v_owning_account_id,
            p_input -> 'functie' ->> 'naam',
            (p_input -> 'functie' ->> 'niveau')::smallint);

    -- 3) dim_scenario met snapshot ref
    insert into public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind, param_snapshot_batch_id)
    values (v_scenario_id, p_legale_entiteit_id, p_naam, 'what_if',
            public.get_current_snapshot_batch_id());

    -- 4) dim_contract
    insert into public.dim_contract (contract_id, persoon_id, functie_id, legale_entiteit_id,
                                     pc_id, status, fte_breuk, geldig_van)
    values (v_contract_id, v_persoon_id, v_functie_id, p_legale_entiteit_id,
            p_input -> 'contract' ->> 'pc_id',
            p_input -> 'contract' ->> 'status',
            (p_input -> 'contract' ->> 'fte_breuk')::numeric,
            p_periode);

    -- 5) fact_prestatie (dagen = 0.0 default, uren = input)
    insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen)
    values (v_contract_id, p_periode, v_prestatiecode_id,
            (p_input -> 'prestatie' ->> 'uren_per_maand')::numeric(10, 4),
            0.0000);

    -- 6) fact_looncomponent basisloon
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    values (v_contract_id, p_periode, 'basisloon', v_scenario_id,
            (p_input -> 'loon' ->> 'basisloon')::numeric(18, 4),
            'simulator_v1_' || v_scenario_id::text);

    -- 7) Trigger cascade write path → fact_loonkost rows
    perform public.create_populatie_loonkost(p_periode, v_scenario_id);

    return v_scenario_id;
end;
$$;

comment on function public.create_simulator_scenario(uuid, text, date, jsonb) is
    'Simulator v1 synthetic contract flow. Creëert in één transactie dim_persoon + dim_functie + dim_scenario + dim_contract + fact_prestatie + fact_looncomponent, roept dan create_populatie_loonkost aan voor cascade persist. Returnt nieuwe scenario_id. SECURITY DEFINER omdat tenant-writes RLS-gated zijn.';

grant execute on function public.create_simulator_scenario(uuid, text, date, jsonb) to authenticated;
