-- ================================================================
-- ISS-089 + ISS-092: cache-invalidation via triggers
-- ================================================================
--
-- ISS-089: authenticated role heeft directe INSERT/UPDATE/DELETE
-- grants op fact_*, dim_scenario, dim_legale_entiteit. RLS bewaakt
-- tenant, maar cache-invalidatie zit alleen in mutation-RPCs. Directe
-- DML (bijv. via Supabase Studio, of setup-action.ts direct .insert
-- op dim_legale_entiteit + dim_scenario) laat mart_populatie_loonkost
-- en mart_loonkloof stale.
--
-- ISS-092: cache-DELETE komt NA `raise` in bulk_import_populatie
-- row-loop. Bij mid-import crash blijft cache stale terwijl
-- transactie mogelijk deels commit'd (afhankelijk van exception path).
--
-- Fix: STATEMENT-level AFTER-triggers op alle tenant-scoped mutations
-- die beide mart-caches invalideren binnen dezelfde transactie. Voor
-- statement-level triggers gebruiken we transition tables
-- (REFERENCING NEW/OLD TABLE) — Postgres 10+ standaard.
--
-- Voordelen:
-- - Werkt ook bij directe DML (Studio, ad-hoc admin, setup-action)
-- - Rollback-safe: als transactie faalt, rollen invalidatie-DELETEs
--   ook terug — cache blijft coherent met source
-- - Statement-level ipv row-level: één invalidation-DELETE per SQL
--   statement, niet per rij (100-row import = 1 invalidation, geen 100)
-- - GROUP BY owning_account_id in de transition table — minimale
--   DELETE-scope
--
-- Redundantie: bulk_import_populatie en clear_tenant_populatie hadden
-- expliciete DELETE FROM mart_* aan het eind. Die blijven staan als
-- defense-in-depth — geen no-ops (de trigger heeft dan al gerund)
-- maar semantisch veilig.
-- ================================================================


-- ================================================================
-- Trigger function: STATEMENT-level, dispatcht op TG_TABLE_NAME + TG_OP
-- ================================================================

create or replace function public.invalidate_marts_for_owning_account()
    returns trigger
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_accounts uuid[];
begin
    -- Verzamel distinct owning_account_ids uit de gewijzigde rijen.
    -- Table-dispatch bepaalt hoe we het account afleiden.
    if TG_TABLE_NAME in ('fact_looncomponent', 'fact_prestatie', 'fact_wagen') then
        -- Via contract → legale_entiteit → owning_account
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r
            join public.dim_contract c on c.contract_id = r.contract_id
            join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r
            join public.dim_contract c on c.contract_id = r.contract_id
            join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME = 'dim_contract' then
        -- Direct via legale_entiteit_id kolom → owning_account
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME = 'dim_scenario' then
        -- Direct via legale_entiteit_id kolom → owning_account
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME in ('dim_persoon', 'dim_functie') then
        -- Direct owning_account_id kolom
        if TG_OP = 'DELETE' then
            select array_agg(distinct owning_account_id) into v_accounts from old_rows;
        else
            select array_agg(distinct owning_account_id) into v_accounts from new_rows;
        end if;

    elsif TG_TABLE_NAME = 'dim_legale_entiteit' then
        -- Direct owning_account_id kolom
        if TG_OP = 'DELETE' then
            select array_agg(distinct owning_account_id) into v_accounts from old_rows;
        else
            select array_agg(distinct owning_account_id) into v_accounts from new_rows;
        end if;
    end if;

    -- Invalideer beide mart-caches voor alle betrokken tenants.
    -- Als v_accounts leeg is (geen rijen gewijzigd, of orphan-refs): no-op.
    if v_accounts is not null and array_length(v_accounts, 1) > 0 then
        delete from public.mart_populatie_loonkost
        where owning_account_id = any(v_accounts);

        delete from public.mart_loonkloof
        where owning_account_id = any(v_accounts);
    end if;

    return null;
end;
$$;

comment on function public.invalidate_marts_for_owning_account() is
    'STATEMENT-level trigger function. Invalideert mart_populatie_loonkost + mart_loonkloof '
    'voor alle owning_accounts van de gewijzigde rijen. Table-dispatch op TG_TABLE_NAME. '
    'Gebruikt transition tables new_rows/old_rows. Werkt binnen dezelfde transactie als '
    'de triggering mutation: rollback rolt cache-DELETE ook terug.';


-- ================================================================
-- Triggers per tabel × operatie
-- ================================================================

-- fact_looncomponent
drop trigger if exists trg_invalidate_marts_fact_looncomponent_ins on public.fact_looncomponent;
create trigger trg_invalidate_marts_fact_looncomponent_ins
    after insert on public.fact_looncomponent
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_fact_looncomponent_upd on public.fact_looncomponent;
create trigger trg_invalidate_marts_fact_looncomponent_upd
    after update on public.fact_looncomponent
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_fact_looncomponent_del on public.fact_looncomponent;
create trigger trg_invalidate_marts_fact_looncomponent_del
    after delete on public.fact_looncomponent
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();


-- fact_prestatie
drop trigger if exists trg_invalidate_marts_fact_prestatie_ins on public.fact_prestatie;
create trigger trg_invalidate_marts_fact_prestatie_ins
    after insert on public.fact_prestatie
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_fact_prestatie_upd on public.fact_prestatie;
create trigger trg_invalidate_marts_fact_prestatie_upd
    after update on public.fact_prestatie
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_fact_prestatie_del on public.fact_prestatie;
create trigger trg_invalidate_marts_fact_prestatie_del
    after delete on public.fact_prestatie
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();


-- fact_wagen
drop trigger if exists trg_invalidate_marts_fact_wagen_ins on public.fact_wagen;
create trigger trg_invalidate_marts_fact_wagen_ins
    after insert on public.fact_wagen
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_fact_wagen_upd on public.fact_wagen;
create trigger trg_invalidate_marts_fact_wagen_upd
    after update on public.fact_wagen
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_fact_wagen_del on public.fact_wagen;
create trigger trg_invalidate_marts_fact_wagen_del
    after delete on public.fact_wagen
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();


-- dim_contract
drop trigger if exists trg_invalidate_marts_dim_contract_ins on public.dim_contract;
create trigger trg_invalidate_marts_dim_contract_ins
    after insert on public.dim_contract
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_dim_contract_upd on public.dim_contract;
create trigger trg_invalidate_marts_dim_contract_upd
    after update on public.dim_contract
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_dim_contract_del on public.dim_contract;
create trigger trg_invalidate_marts_dim_contract_del
    after delete on public.dim_contract
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();


-- dim_persoon
drop trigger if exists trg_invalidate_marts_dim_persoon_ins on public.dim_persoon;
create trigger trg_invalidate_marts_dim_persoon_ins
    after insert on public.dim_persoon
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_dim_persoon_upd on public.dim_persoon;
create trigger trg_invalidate_marts_dim_persoon_upd
    after update on public.dim_persoon
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_dim_persoon_del on public.dim_persoon;
create trigger trg_invalidate_marts_dim_persoon_del
    after delete on public.dim_persoon
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();


-- dim_functie
drop trigger if exists trg_invalidate_marts_dim_functie_ins on public.dim_functie;
create trigger trg_invalidate_marts_dim_functie_ins
    after insert on public.dim_functie
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_dim_functie_upd on public.dim_functie;
create trigger trg_invalidate_marts_dim_functie_upd
    after update on public.dim_functie
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_dim_functie_del on public.dim_functie;
create trigger trg_invalidate_marts_dim_functie_del
    after delete on public.dim_functie
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();


-- dim_scenario
drop trigger if exists trg_invalidate_marts_dim_scenario_ins on public.dim_scenario;
create trigger trg_invalidate_marts_dim_scenario_ins
    after insert on public.dim_scenario
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_dim_scenario_upd on public.dim_scenario;
create trigger trg_invalidate_marts_dim_scenario_upd
    after update on public.dim_scenario
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

drop trigger if exists trg_invalidate_marts_dim_scenario_del on public.dim_scenario;
create trigger trg_invalidate_marts_dim_scenario_del
    after delete on public.dim_scenario
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();


-- dim_legale_entiteit (alleen DELETE — INSERT/UPDATE van entiteit-config
-- verandert geen cascade-berekening; DELETE cascade't naar afhankelijke
-- rows waarvan de eigen triggers al vuren, maar we willen ook zeker weten
-- dat de eigen mart-rijen weg zijn).
drop trigger if exists trg_invalidate_marts_dim_legale_entiteit_del on public.dim_legale_entiteit;
create trigger trg_invalidate_marts_dim_legale_entiteit_del
    after delete on public.dim_legale_entiteit
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();
