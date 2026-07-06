-- ================================================================
-- ISS-100: dim_legale_entiteit trigger uitbreiden naar INSERT/UPDATE/DELETE
-- ================================================================
--
-- ISS-089 migration zette per ongeluk een DELETE-only trigger op
-- dim_legale_entiteit met comment "INSERT/UPDATE van entiteit-config
-- verandert geen cascade-berekening". Dat is FOUT: werkgeverscategorie
-- stuurt RSZ-basisbijdrage; gewest stuurt doelgroepvermindering (VDAB/
-- Actiris/Forem). authenticated heeft bovendien direct UPDATE-recht via
-- basejump grants uit 20260705220000_grant_insert_dim_legale_entiteit.
--
-- Fix: drop bestaande DELETE-only trigger, vervang door 3 triggers voor
-- INSERT / UPDATE / DELETE. Bij UPDATE: als owning_account_id verandert
-- (unlikely maar denkbaar via admin), invalideer OUD + NIEUW account.
-- ================================================================


-- ================================================================
-- Trigger function uitbreiden om owning_account_id shift bij UPDATE te dekken
-- ================================================================

-- De bestaande invalidate_marts_for_owning_account leest new_rows OF old_rows
-- afhankelijk van TG_OP. Voor UPDATE waar owning_account_id verandert, moeten
-- we BEIDE. Simpelste patch: dispatch UPDATE naar een variant die beide leest.

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
    if TG_TABLE_NAME in ('fact_looncomponent', 'fact_prestatie', 'fact_wagen') then
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r
            join public.dim_contract c on c.contract_id = r.contract_id
            join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id;
        elsif TG_OP = 'UPDATE' then
            -- UPDATE: neem OUD + NIEUW om row-migration te dekken (contract-move)
            select array_agg(distinct le.owning_account_id) into v_accounts
            from (
                select contract_id from old_rows
                union
                select contract_id from new_rows
            ) r
            join public.dim_contract c on c.contract_id = r.contract_id
            join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r
            join public.dim_contract c on c.contract_id = r.contract_id
            join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME = 'dim_contract' then
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from (
                select legale_entiteit_id from old_rows
                union
                select legale_entiteit_id from new_rows
            ) r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME = 'dim_scenario' then
        if TG_OP = 'DELETE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from old_rows r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct le.owning_account_id) into v_accounts
            from (
                select legale_entiteit_id from old_rows
                union
                select legale_entiteit_id from new_rows
            ) r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        else
            select array_agg(distinct le.owning_account_id) into v_accounts
            from new_rows r
            join public.dim_legale_entiteit le on le.legale_entiteit_id = r.legale_entiteit_id;
        end if;

    elsif TG_TABLE_NAME in ('dim_persoon', 'dim_functie') then
        if TG_OP = 'DELETE' then
            select array_agg(distinct owning_account_id) into v_accounts from old_rows;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct owning_account_id) into v_accounts from (
                select owning_account_id from old_rows
                union
                select owning_account_id from new_rows
            ) r;
        else
            select array_agg(distinct owning_account_id) into v_accounts from new_rows;
        end if;

    elsif TG_TABLE_NAME = 'dim_legale_entiteit' then
        -- ISS-100: nu ook INSERT + UPDATE. Bij UPDATE ook oude tenant meenemen
        -- als owning_account_id verandert (admin-move).
        if TG_OP = 'DELETE' then
            select array_agg(distinct owning_account_id) into v_accounts from old_rows;
        elsif TG_OP = 'UPDATE' then
            select array_agg(distinct owning_account_id) into v_accounts from (
                select owning_account_id from old_rows
                union
                select owning_account_id from new_rows
            ) r;
        else
            select array_agg(distinct owning_account_id) into v_accounts from new_rows;
        end if;
    end if;

    if v_accounts is not null and array_length(v_accounts, 1) > 0 then
        delete from public.mart_populatie_loonkost
        where owning_account_id = any(v_accounts);

        delete from public.mart_loonkloof
        where owning_account_id = any(v_accounts);
    end if;

    return null;
end;
$$;


-- ================================================================
-- dim_legale_entiteit triggers uitbreiden naar INSERT + UPDATE + DELETE
-- ================================================================

drop trigger if exists trg_invalidate_marts_dim_legale_entiteit_del on public.dim_legale_entiteit;

create trigger trg_invalidate_marts_dim_legale_entiteit_ins
    after insert on public.dim_legale_entiteit
    referencing new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

create trigger trg_invalidate_marts_dim_legale_entiteit_upd
    after update on public.dim_legale_entiteit
    referencing old table as old_rows new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

create trigger trg_invalidate_marts_dim_legale_entiteit_del
    after delete on public.dim_legale_entiteit
    referencing old table as old_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();


-- ================================================================
-- Bestaande UPDATE-triggers op andere tabellen ook uitbreiden met OLD table
-- ================================================================
-- ISS-100 patch: UPDATE-triggers uit ISS-089 hebben alleen NEW table.
-- Voor row-migration (bijv. contract wisselt van legale_entiteit) moeten
-- we OUD én NIEUW invalideren. Vervang alle UPDATE-triggers om ook OLD
-- transition table te hebben.

-- fact_looncomponent
drop trigger if exists trg_invalidate_marts_fact_looncomponent_upd on public.fact_looncomponent;
create trigger trg_invalidate_marts_fact_looncomponent_upd
    after update on public.fact_looncomponent
    referencing old table as old_rows new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

-- fact_prestatie
drop trigger if exists trg_invalidate_marts_fact_prestatie_upd on public.fact_prestatie;
create trigger trg_invalidate_marts_fact_prestatie_upd
    after update on public.fact_prestatie
    referencing old table as old_rows new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

-- fact_wagen
drop trigger if exists trg_invalidate_marts_fact_wagen_upd on public.fact_wagen;
create trigger trg_invalidate_marts_fact_wagen_upd
    after update on public.fact_wagen
    referencing old table as old_rows new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

-- dim_contract
drop trigger if exists trg_invalidate_marts_dim_contract_upd on public.dim_contract;
create trigger trg_invalidate_marts_dim_contract_upd
    after update on public.dim_contract
    referencing old table as old_rows new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

-- dim_persoon
drop trigger if exists trg_invalidate_marts_dim_persoon_upd on public.dim_persoon;
create trigger trg_invalidate_marts_dim_persoon_upd
    after update on public.dim_persoon
    referencing old table as old_rows new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

-- dim_functie
drop trigger if exists trg_invalidate_marts_dim_functie_upd on public.dim_functie;
create trigger trg_invalidate_marts_dim_functie_upd
    after update on public.dim_functie
    referencing old table as old_rows new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();

-- dim_scenario
drop trigger if exists trg_invalidate_marts_dim_scenario_upd on public.dim_scenario;
create trigger trg_invalidate_marts_dim_scenario_upd
    after update on public.dim_scenario
    referencing old table as old_rows new table as new_rows
    for each statement
    execute function public.invalidate_marts_for_owning_account();
