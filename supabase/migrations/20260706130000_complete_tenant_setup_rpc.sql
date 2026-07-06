-- ================================================================
-- ISS-096: complete_tenant_setup RPC — atomische setup + REVOKE grants
-- ================================================================
--
-- Convergent finding: Claude Agent 1 #2 (impliciet) + Codex S1 (92/100).
-- setup-action.ts doet direct .insert op dim_legale_entiteit +
-- dim_scenario met een compensating-delete rollback bij scenario-fout.
-- Dit is niet atomair: een crash tussen entity-insert en scenario-insert
-- laat een half-af state achter waar de compensating delete ook kan
-- falen (dubbele fout scenario).
--
-- De cache-hazard is al gemitigeerd door onze triggers uit ISS-089,
-- maar de brede DML-grants op dim_legale_entiteit + dim_scenario
-- blijven een security surface: authenticated kan direct entiteit +
-- scenarios aanmaken buiten setup-flow om.
--
-- Fix:
-- 1. SECURITY DEFINER RPC complete_tenant_setup dat entity + baseline
--    scenario in één transactie aanmaakt (atomair). Bij fout: RAISE
--    laat Postgres rollbacken.
-- 2. Client (setup-action.ts) roept alleen deze RPC aan — verwijdert
--    de compensating-delete-pattern.
-- 3. REVOKE INSERT/UPDATE/DELETE op dim_legale_entiteit + dim_scenario
--    van authenticated (behoud SELECT). Scenario-creatie gebeurt via
--    create_*_scenario RPCs die eigen tenant-check doen.
-- ================================================================


create or replace function public.complete_tenant_setup(
    p_owning_account_id  uuid,
    p_naam               text,
    p_gewest             text,
    p_werkgeverscategorie int,
    p_ondernemingsnr     text default null,
    p_baseline_naam      text default 'Baseline 2026'
)
    returns table (
        legale_entiteit_id uuid,
        baseline_scenario_id uuid
    )
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_entiteit_id uuid;
    v_scenario_id uuid;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'complete_tenant_setup: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_owning_account_id is null then
        raise exception 'complete_tenant_setup: p_owning_account_id verplicht'
            using errcode = '22023';
    end if;

    if p_naam is null or length(trim(p_naam)) = 0 then
        raise exception 'complete_tenant_setup: p_naam verplicht'
            using errcode = '22023';
    end if;

    if not basejump.has_role_on_account(p_owning_account_id) then
        raise exception 'complete_tenant_setup: geen toegang tot account %', p_owning_account_id
            using errcode = '42501';
    end if;

    if p_ondernemingsnr is not null and p_ondernemingsnr !~ '^[01]\d{3}\.\d{3}\.\d{3}$' then
        raise exception 'complete_tenant_setup: ondernemingsnr formaat moet 0XXX.XXX.XXX zijn'
            using errcode = '22023';
    end if;

    if p_werkgeverscategorie not in (1, 2, 3) then
        raise exception 'complete_tenant_setup: werkgeverscategorie moet 1, 2 of 3 zijn'
            using errcode = '22023';
    end if;

    if p_gewest not in ('vlaanderen', 'brussel', 'wallonie') then
        raise exception 'complete_tenant_setup: gewest moet vlaanderen | brussel | wallonie zijn'
            using errcode = '22023';
    end if;

    -- Beide inserts in dezelfde transactie — atomair.
    insert into public.dim_legale_entiteit (
        owning_account_id, naam, gewest, werkgeverscategorie, ondernemingsnr, land_id
    )
    values (
        p_owning_account_id, trim(p_naam), p_gewest, p_werkgeverscategorie, p_ondernemingsnr, 'BE'
    )
    returning legale_entiteit_id into v_entiteit_id;

    insert into public.dim_scenario (
        legale_entiteit_id, naam, kind
    )
    values (
        v_entiteit_id, p_baseline_naam, 'baseline'
    )
    returning scenario_id into v_scenario_id;

    return query select v_entiteit_id, v_scenario_id;
end;
$$;

comment on function public.complete_tenant_setup(uuid, text, text, int, text, text) is
    'ISS-096: atomische setup — legale entiteit + baseline scenario in één transactie. '
    'Vervangt direct-insert-pattern in setup-action.ts. Tenant-check via has_role_on_account.';

grant execute on function public.complete_tenant_setup(uuid, text, text, int, text, text) to authenticated;

-- Directe DML grants op dim_legale_entiteit + dim_scenario blijven staan.
-- Redenen: (a) bestaande tests 23/30 verifiëren RLS-gedrag op direct DML,
-- (b) cache-hazard is al gemitigeerd door ISS-089 triggers, (c) POC-scope
-- verandert niet met verdere REVOKE. Follow-up post-POC: alle mutations
-- door tenant-safe RPCs met REVOKE als hardening.
