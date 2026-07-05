-- ================================================================
-- bulk_import_populatie RPC — één-transactie batch insert
-- ================================================================
--
-- Vervangt de N+1 HTTP round-trip pattern (3× insert per rij × 1000
-- rijen = 3000 HTTP calls, ~72s op Vercel→Supabase) door één RPC call
-- die alle inserts in dezelfde Postgres session doet.
--
-- Verwachte tijd voor 1000 rijen: ~1-2s (10-40× sneller).
--
-- Geen cascade berekeningen tijdens import — dat blijft on-demand
-- via cascade_populatie_snapshot bij page load, of via een aparte
-- refresh trigger later.
--
-- Input formaat p_rows:
--   [
--     {"naam": "...", "geslacht": "m|v", "geboortedatum": "YYYY-MM-DD",
--      "opleidingsniveau": "...", "team": "...", "status": "bediende|arbeider",
--      "pc": "200", "bruto": 3500},
--     ...
--   ]
-- ================================================================

create or replace function public.bulk_import_populatie(
    p_legale_entiteit_id uuid,
    p_scenario_id uuid,
    p_rows jsonb,
    p_periode date default '2024-06-01',
    p_geldig_van date default '2023-01-01'
)
    returns table (
        created integer,
        skipped integer,
        errors text[]
    )
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_owning_account uuid;
    v_functie_cache jsonb := '{}'::jsonb;
    v_persoon_id uuid;
    v_contract_id uuid;
    v_functie_id uuid;
    v_created integer := 0;
    v_skipped integer := 0;
    v_errors text[] := '{}';
    v_row record;
    v_existing_functie record;
begin
    -- Auth check
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'bulk_import_populatie: authenticated caller required'
            using errcode = '42501';
    end if;

    -- Tenant check
    select owning_account_id into v_owning_account
    from public.dim_legale_entiteit
    where legale_entiteit_id = p_legale_entiteit_id;

    if v_owning_account is null then
        raise exception 'bulk_import_populatie: entiteit % niet gevonden', p_legale_entiteit_id
            using errcode = '02000';
    end if;

    if not basejump.has_role_on_account(v_owning_account) then
        raise exception 'bulk_import_populatie: geen toegang tot deze entiteit'
            using errcode = '42501';
    end if;

    -- Cache bestaande functies voor deze tenant (case-insensitive lookup)
    for v_existing_functie in
        select functienaam, functie_id from public.dim_functie where owning_account_id = v_owning_account
    loop
        v_functie_cache := v_functie_cache || jsonb_build_object(
            lower(v_existing_functie.functienaam),
            v_existing_functie.functie_id::text
        );
    end loop;

    -- Loop over input rows
    for v_row in
        select * from jsonb_to_recordset(p_rows) as x(
            naam text,
            geslacht text,
            geboortedatum date,
            opleidingsniveau text,
            team text,
            status text,
            pc text,
            bruto numeric
        )
    loop
        begin
            -- Validatie
            if v_row.naam is null or v_row.naam = '' then
                v_errors := v_errors || 'rij zonder naam';
                v_skipped := v_skipped + 1;
                continue;
            end if;
            if v_row.geslacht not in ('m', 'v', 'x') then
                v_errors := v_errors || (v_row.naam || ': ongeldig geslacht');
                v_skipped := v_skipped + 1;
                continue;
            end if;
            if v_row.bruto is null or v_row.bruto <= 0 then
                v_errors := v_errors || (v_row.naam || ': bruto <= 0');
                v_skipped := v_skipped + 1;
                continue;
            end if;

            -- Resolve of create functie (case-insensitive)
            v_functie_id := (v_functie_cache ->> lower(v_row.team))::uuid;
            if v_functie_id is null then
                insert into public.dim_functie (owning_account_id, functienaam, functieniveau)
                values (v_owning_account, v_row.team, 10)
                returning functie_id into v_functie_id;
                v_functie_cache := v_functie_cache || jsonb_build_object(lower(v_row.team), v_functie_id::text);
            end if;

            -- Insert persoon
            insert into public.dim_persoon (owning_account_id, geslacht, geboortedatum, opleidingsniveau)
            values (v_owning_account, v_row.geslacht, v_row.geboortedatum, coalesce(v_row.opleidingsniveau, 'middel_geschoold'))
            returning persoon_id into v_persoon_id;

            -- Insert contract
            insert into public.dim_contract (
                persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van
            )
            values (
                v_persoon_id,
                p_legale_entiteit_id,
                v_functie_id,
                coalesce(v_row.pc, case when v_row.status = 'arbeider' then '124' else '200' end),
                coalesce(v_row.status, 'bediende'),
                1.0,
                p_geldig_van
            )
            returning contract_id into v_contract_id;

            -- Insert basisloon
            insert into public.fact_looncomponent (
                contract_id, periode, component_id, scenario_id, bedrag
            )
            values (v_contract_id, p_periode, 'basisloon', p_scenario_id, v_row.bruto);

            v_created := v_created + 1;
        exception
            when others then
                v_errors := v_errors || (coalesce(v_row.naam, '?') || ': ' || SQLERRM);
                v_skipped := v_skipped + 1;
        end;
    end loop;

    return query select v_created, v_skipped, v_errors;
end;
$$;

revoke execute on function public.bulk_import_populatie(uuid, uuid, jsonb, date, date) from public;
grant execute on function public.bulk_import_populatie(uuid, uuid, jsonb, date, date) to authenticated;

comment on function public.bulk_import_populatie(uuid, uuid, jsonb, date, date) is
    'One-transaction batch insert voor populatie: dim_persoon + dim_contract + fact_looncomponent. Elimineert per-row HTTP overhead. Cached functies lookup. Per-row exception handling zodat één bad row de hele batch niet stopt.';
