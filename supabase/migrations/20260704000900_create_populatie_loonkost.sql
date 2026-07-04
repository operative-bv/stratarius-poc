-- ================================================================
-- T-055: create_populatie_loonkost RPC — populatie write path
-- ================================================================
--
-- Persist cascade output naar fact_loonkost voor alle contracten in tenant
-- die matchen op scenario + filters. Idempotent via ON CONFLICT.
--
-- Design:
--   - SECURITY DEFINER: fact_loonkost writes zijn REVOKED van authenticated;
--     alleen deze SDF-functie mag schrijven. RLS-tenanting geldt op de SELECT-
--     kant via cascade_populatie_snapshot (die respecteert dim_contract/
--     dim_legale_entiteit tenant policies).
--   - 7 kostenblok rijen per contract (bruto, werkgevers_rsz, vakantiegeld,
--     ejp, extralegaal, wagen_tco, arbeidsongevallen).
--   - ON CONFLICT (contract_id, periode, kostenblok, scenario_id) DO UPDATE:
--     herhaalde call werkt bestaande bedragen bij en zet cascade_run_at op now().
--   - snapshot_batch_id via get_current_snapshot_batch_id() (T-054); auto-create
--     nieuwe snapshot als er nog geen is (reproducibility guarantee).
--
-- Kostenblok mapping (uit cascade_populatie_snapshot kolommen):
--   bruto            = bruto
--   werkgevers_rsz   = stap2 - stap3 - stap4 + stap5    (RSZ som)
--   vakantiegeld     = stap6
--   ejp              = cascade_stap6b_eindejaarspremie(bruto, pc_id, periode)
--   extralegaal      = stap7
--   wagen_tco        = stap8
--   arbeidsongevallen= stap9
--
-- Security model:
--   Function GRANT EXECUTE aan authenticated. SECURITY DEFINER met pinned
--   search_path voorkomt privilege escalation. Interne SELECT via
--   cascade_populatie_snapshot respecteert tenant RLS — caller kan alleen
--   voor eigen tenant contracten schrijven.
--
-- Rollback:
--   DROP FUNCTION public.create_populatie_loonkost(date, uuid, jsonb);


create or replace function public.create_populatie_loonkost(
    p_periode     date,
    p_scenario_id uuid,
    p_filters     jsonb default '{}'::jsonb
)
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_snapshot_batch_id uuid := public.get_current_snapshot_batch_id();
    v_rowcount int := 0;
begin
    -- Auto-create parameter snapshot als er nog geen bestaat (reproducibility).
    if v_snapshot_batch_id is null then
        v_snapshot_batch_id := public.create_parameter_snapshot('auto by create_populatie_loonkost');
    end if;

    -- Insert 7 kostenblokken per contract via cross-join met kostenblok array.
    -- ON CONFLICT DO UPDATE maakt herhaalde call idempotent.
    insert into public.fact_loonkost (
        contract_id, periode, kostenblok, scenario_id, bedrag, snapshot_batch_id
    )
    select
        s.contract_id,
        p_periode,
        blok,
        p_scenario_id,
        (case blok
            when 'bruto' then s.bruto
            when 'werkgevers_rsz' then s.stap2_basis_rsz - s.stap3_vermindering - s.stap4_doelgroep + s.stap5_bijzondere
            when 'vakantiegeld' then s.stap6_vakantiegeld
            when 'ejp' then coalesce(public.cascade_stap6b_eindejaarspremie(s.bruto, s.pc_id, p_periode), 0)
            when 'extralegaal' then s.stap7_extralegaal
            when 'wagen_tco' then s.stap8_wagen
            when 'arbeidsongevallen' then s.stap9_arbeidsongevallen
        end)::numeric(18, 4),
        v_snapshot_batch_id
    from public.cascade_populatie_snapshot(p_periode, p_scenario_id, p_filters) s
    cross join unnest(array[
        'bruto', 'werkgevers_rsz', 'vakantiegeld',
        'ejp', 'extralegaal', 'wagen_tco', 'arbeidsongevallen'
    ]) as blok
    on conflict (contract_id, periode, kostenblok, scenario_id) do update
    set bedrag = excluded.bedrag,
        snapshot_batch_id = excluded.snapshot_batch_id,
        cascade_run_at = now(),
        updated_at = now();

    get diagnostics v_rowcount = row_count;

    return jsonb_build_object(
        'rowcount', v_rowcount,
        'snapshot_batch_id', v_snapshot_batch_id,
        'run_at', now()
    );
end;
$$;

comment on function public.create_populatie_loonkost(date, uuid, jsonb) is
    'Populatie write path naar fact_loonkost. Enumeert contracten via cascade_populatie_snapshot (RLS-tenanted) en schrijft 7 kostenblok rijen per contract per scenario. SECURITY DEFINER omdat fact_loonkost writes REVOKED zijn. Auto-creates parameter snapshot voor reproducibility als geen bestaat. Idempotent via ON CONFLICT (contract_id, periode, kostenblok, scenario_id) DO UPDATE.';

grant execute on function public.create_populatie_loonkost(date, uuid, jsonb) to authenticated;
