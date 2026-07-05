-- ================================================================
-- Cleanup: fact_loonkost + create_populatie_loonkost weg
-- ================================================================
--
-- fact_loonkost was de oude persist-cascade tabel (7 kostenblok categorieën).
-- mart_populatie_loonkost (20260706000000) heeft die rol overgenomen met
-- fijnere granulariteit (18 cascade-output kolommen) + per-tenant RLS +
-- auto-invalidate via mutatie-RPCs.
--
-- Geen enkele UI-page leest van fact_loonkost. create_populatie_loonkost
-- werd alleen aangeroepen door:
-- 1. create_simulator_scenario (final step) — verwijder die call
-- 2. pgTAP test 60 (regression test) — pas de test aan
--
-- Impact:
-- - fact_loonkost tabel verdwijnt (nul UI-usage)
-- - create_simulator_scenario returnt scenario_id zonder cascade-persist,
--   maar de populatie page auto-populate cache doet dat werk on-demand
-- ================================================================

-- 1. Update create_simulator_scenario om create_populatie_loonkost call te droppen.
-- create_simulator_scenario returnt scenario_id; cache wordt automatisch
-- gepopuleerd op eerste populatie-page visit.

create or replace function public.create_simulator_scenario(
    p_legale_entiteit_id uuid,
    p_naam text,
    p_periode date,
    p_input jsonb
)
    returns uuid
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_persoon_id uuid;
    v_functie_id uuid;
    v_scenario_id uuid;
    v_contract_id uuid;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'create_simulator_scenario: authenticated caller required'
            using errcode = '42501';
    end if;

    select owning_account_id into v_owning_account
    from public.dim_legale_entiteit
    where legale_entiteit_id = p_legale_entiteit_id;

    if v_owning_account is null then
        raise exception 'create_simulator_scenario: entiteit % niet gevonden', p_legale_entiteit_id
            using errcode = '02000';
    end if;

    if not basejump.has_role_on_account(v_owning_account) then
        raise exception 'create_simulator_scenario: geen toegang tot entiteit %', p_legale_entiteit_id
            using errcode = '42501';
    end if;

    -- 1) dim_persoon
    insert into public.dim_persoon (owning_account_id, geslacht, geboortedatum, opleidingsniveau)
    values (
        v_owning_account,
        (p_input -> 'persoon' ->> 'geslacht'),
        (p_input -> 'persoon' ->> 'geboortedatum')::date,
        (p_input -> 'persoon' ->> 'opleiding')
    )
    returning persoon_id into v_persoon_id;

    -- 2) dim_functie
    insert into public.dim_functie (owning_account_id, functienaam, functieniveau)
    values (
        v_owning_account,
        p_input -> 'functie' ->> 'naam',
        (p_input -> 'functie' ->> 'niveau')::smallint
    )
    returning functie_id into v_functie_id;

    -- 3) dim_scenario (kind='simulator' zit niet in enum; gebruik 'what_if')
    insert into public.dim_scenario (legale_entiteit_id, naam, kind)
    values (p_legale_entiteit_id, p_naam, 'what_if')
    returning scenario_id into v_scenario_id;

    -- 4) dim_contract
    insert into public.dim_contract (
        persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van
    )
    values (
        v_persoon_id, p_legale_entiteit_id, v_functie_id,
        p_input -> 'contract' ->> 'pc_id',
        p_input -> 'contract' ->> 'status',
        (p_input -> 'contract' ->> 'fte_breuk')::numeric(6, 4),
        p_periode
    )
    returning contract_id into v_contract_id;

    -- 5) fact_prestatie (voor μ berekening)
    insert into public.fact_prestatie (contract_id, periode, prestatiecode_id, uren, dagen)
    values (
        v_contract_id, p_periode, 'normaal_gewerkt',
        (p_input -> 'prestatie' ->> 'uren_per_maand')::numeric(10, 4),
        20.0000 -- default dagen (numeric(6,4))
    );

    -- 6) fact_looncomponent (basisloon)
    insert into public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag, bron_ref)
    values (v_contract_id, p_periode, 'basisloon', v_scenario_id,
            (p_input -> 'loon' ->> 'basisloon')::numeric(18, 4),
            'simulator_v1_' || v_scenario_id::text);

    -- 7) Geen cascade-persist call meer: mart_populatie_loonkost cache wordt
    --    automatisch gepopuleerd op eerste populatie-page visit (auto-populate
    --    pattern in populatie-results.tsx).

    return v_scenario_id;
end;
$$;

comment on function public.create_simulator_scenario(uuid, text, date, jsonb) is
    'Simulator synthetic contract flow. Creëert dim_persoon + dim_functie + dim_scenario + dim_contract + fact_prestatie + fact_looncomponent. Cache wordt automatisch gebouwd op eerste populatie-page visit (mart_populatie_loonkost auto-populate). Returnt nieuwe scenario_id.';


-- 2. Drop create_populatie_loonkost function
drop function if exists public.create_populatie_loonkost(date, uuid, jsonb) cascade;
drop function if exists public.create_populatie_loonkost(date, uuid) cascade;

-- 3. Drop fact_loonkost tabel
drop table if exists public.fact_loonkost cascade;
