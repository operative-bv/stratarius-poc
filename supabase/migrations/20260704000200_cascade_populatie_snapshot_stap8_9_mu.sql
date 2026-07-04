-- ================================================================
-- T-058: cascade_populatie_snapshot uitbreiden met stap 8, stap 9, en echte mu
-- ================================================================
--
-- Wijzigingen tov T-039 versie (20260703340000_cascade_populatie_snapshot.sql):
--   1. Nieuwe kolommen in RETURNS TABLE:
--      - mu numeric(6,4)  -- effectieve prestatiebreuk per contract via mu_van_prestatie()
--      - stap8_wagen numeric(18,4)  -- CO2-solidariteitsbijdrage per contract
--      - stap9_arbeidsongevallen numeric(18,4)  -- arbeidsongevallenverzekering
--   2. Stap 3 aanroep gebruikt echte mu ipv hardcoded 1.0000 (Principe IV correctie).
--   3. totaal_patronale_kost en tco sommeren stap8 + stap9.
--
-- BUITEN scope T-058 (blijven bestaan tot follow-up, gemeld via nieuwe issue):
--   - stap4_doelgroepverminderingen wordt niet aangeroepen (missing pre-existing).
--   - stap7_extralegaal is teruggegeven maar niet gesommeerd in totaal/tco.
--   Beide zijn structurele bugs die de gerapporteerde TCO scheef trekken.
--
-- Postgres kan een functie's RETURNS TABLE niet CREATE OR REPLACE-en zodra kolommen
-- toegevoegd worden. Migration DROPT eerst de oude signature, CREATE'T dan opnieuw.
--
-- Rollback:
--   Revert naar 20260703340000_cascade_populatie_snapshot.sql definitie.


-- ================================================================
-- 1) DROP oude functie (return-type structural change)
-- ================================================================

drop function if exists public.cascade_populatie_snapshot(date, uuid, uuid);


-- ================================================================
-- 2) CREATE nieuwe functie met uitgebreide return-type
-- ================================================================

create or replace function public.cascade_populatie_snapshot(
    p_periode date,
    p_scenario_id uuid default null,
    p_functie_id uuid default null
)
    returns table (
        contract_id uuid,
        persoon_id uuid,
        pc_id text,
        status text,
        werkgeverscategorie smallint,
        functienaam text,
        mu numeric(6, 4),
        bruto numeric(18, 4),
        stap2_basis_rsz numeric(18, 4),
        stap3_vermindering numeric(18, 4),
        stap5_bijzondere numeric(18, 4),
        stap6_vakantiegeld numeric(18, 4),
        stap7_extralegaal numeric(18, 4),
        stap8_wagen numeric(18, 4),
        stap9_arbeidsongevallen numeric(18, 4),
        totaal_patronale_kost numeric(18, 4),
        tco numeric(18, 4)
    )
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    with contracten as (
        select
            c.contract_id,
            c.persoon_id,
            c.pc_id,
            c.status,
            le.werkgeverscategorie,
            f.functienaam,
            -- mu per contract via mu_van_prestatie; fallback naar 1.0000 wanneer geen
            -- fact_prestatie beschikbaar is (contract zonder loggegevens = voltijd-assumption).
            coalesce(public.mu_van_prestatie(c.contract_id, p_periode), 1.0000)::numeric(6, 4) as mu,
            -- Bruto = som van is_basisloon components per contract, scenario-filtered.
            coalesce((
                select sum(fl.bedrag)
                from public.fact_looncomponent fl
                join public.dim_looncomponent dl on dl.component_id = fl.component_id
                where fl.contract_id = c.contract_id
                  and fl.periode = date_trunc('month', p_periode)::date
                  and (p_scenario_id is null or fl.scenario_id = p_scenario_id)
                  and dl.is_basisloon
            ), 0)::numeric(18, 4) as bruto
        from public.dim_contract c
        join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id
        join public.dim_functie f on f.functie_id = c.functie_id
        where c.geldig_van <= p_periode
          and (c.geldig_tot is null or c.geldig_tot > p_periode)
          and (p_functie_id is null or c.functie_id = p_functie_id)
    ),
    berekend as (
        select
            ct.contract_id,
            ct.persoon_id,
            ct.pc_id,
            ct.status,
            ct.werkgeverscategorie,
            ct.functienaam,
            ct.mu,
            ct.bruto,
            coalesce(
                public.cascade_stap2_basis_patronale_rsz(ct.bruto, ct.status, ct.werkgeverscategorie, p_periode),
                0
            )::numeric(18, 4) as stap2_basis_rsz,
            -- Stap 3: echte mu (was hardcoded 1.0000 — Principe IV violation gefixed).
            coalesce(
                public.cascade_stap3_structurele_vermindering(ct.bruto * 3, ct.mu, ct.werkgeverscategorie, p_periode),
                0
            )::numeric(18, 4) as stap3_vermindering,
            coalesce(
                public.cascade_stap5_bijzondere_bijdragen(ct.bruto, p_periode),
                0
            )::numeric(18, 4) as stap5_bijzondere,
            coalesce(
                public.cascade_stap6_vakantiegeld(ct.bruto, ct.status, p_periode),
                0
            )::numeric(18, 4) as stap6_vakantiegeld,
            -- Stap 7 inline (pattern uit T-039 versie behouden). NB: niet gesommeerd
            -- in totaal_patronale_kost — pre-existing bug, ISS follow-up.
            coalesce((
                select sum(fl.bedrag * pe.taks_pct)
                from public.fact_looncomponent fl
                join public.dim_looncomponent dl on dl.component_id = fl.component_id
                join public.param_extralegaal pe on pe.voordeeltype = dl.component_id
                where fl.contract_id = ct.contract_id
                  and fl.periode = date_trunc('month', p_periode)::date
                  and (p_scenario_id is null or fl.scenario_id = p_scenario_id)
                  and dl.familie = 'extralegaal'
                  and p_periode >= pe.geldig_van
                  and (pe.geldig_tot is null or p_periode < pe.geldig_tot)
            ), 0)::numeric(18, 4) as stap7_extralegaal,
            -- Stap 8 wagen: coalesce naar 0 wanneer contract geen fact_wagen heeft.
            coalesce((
                select public.cascade_stap8_wagen_solidariteitsbijdrage(fw.co2_g_km, fw.brandstoftype, p_periode)
                from public.fact_wagen fw
                where fw.contract_id = ct.contract_id
                  and fw.periode = date_trunc('month', p_periode)::date
                limit 1
            ), 0)::numeric(18, 4) as stap8_wagen,
            -- Stap 9 arbeidsongevallen: PC-specifiek tarief; NULL wanneer PC geen seed heeft.
            coalesce(
                public.cascade_stap9_arbeidsongevallen(ct.bruto, ct.pc_id, p_periode),
                0
            )::numeric(18, 4) as stap9_arbeidsongevallen
        from contracten ct
    )
    select
        b.contract_id,
        b.persoon_id,
        b.pc_id,
        b.status,
        b.werkgeverscategorie,
        b.functienaam,
        b.mu,
        b.bruto,
        b.stap2_basis_rsz,
        b.stap3_vermindering,
        b.stap5_bijzondere,
        b.stap6_vakantiegeld,
        b.stap7_extralegaal,
        b.stap8_wagen,
        b.stap9_arbeidsongevallen,
        -- Totaal patronale kost: stap2 - stap3 + stap5 + stap6 + stap8 + stap9.
        -- stap7 en stap4 zijn out-of-scope voor T-058 (ISS follow-up).
        (
            b.stap2_basis_rsz
            - b.stap3_vermindering
            + b.stap5_bijzondere
            + b.stap6_vakantiegeld
            + b.stap8_wagen
            + b.stap9_arbeidsongevallen
        )::numeric(18, 4) as totaal_patronale_kost,
        -- TCO = bruto + totaal patronale kost.
        (
            b.bruto
            + b.stap2_basis_rsz
            - b.stap3_vermindering
            + b.stap5_bijzondere
            + b.stap6_vakantiegeld
            + b.stap8_wagen
            + b.stap9_arbeidsongevallen
        )::numeric(18, 4) as tco
    from berekend b;
$$;

comment on function public.cascade_populatie_snapshot(date, uuid, uuid) is
    'Populatie-snapshot: alle contracten in tenant + volledige cascade output (stap 2, 3, 5, 6, 7, 8, 9) + mu per contract. RLS filtert via dim_contract / dim_legale_entiteit tenant-scoping. T-058 uitbreiding: echte mu (mu_van_prestatie) ipv 1.0000, stap 8 wagen-solidariteitsbijdrage, stap 9 arbeidsongevallen. Stap 4 en stap 7 nog niet in totaal_patronale_kost (ISS follow-up).';

grant execute on function public.cascade_populatie_snapshot(date, uuid, uuid) to authenticated;
