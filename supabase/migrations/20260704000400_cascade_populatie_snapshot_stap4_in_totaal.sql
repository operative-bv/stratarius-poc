-- ================================================================
-- ISS-076 fix: cascade_populatie_snapshot volledige TCO
-- ================================================================
--
-- Wijzigingen tov T-058 versie:
--   1. Nieuwe kolom stap4_doelgroep numeric(18,4) tussen stap3 en stap5.
--   2. cascade_stap4_doelgroepverminderingen(contract_id, bruto, mu, periode)
--      wordt aangeroepen (was pre-existing gap sinds T-039).
--   3. totaal_patronale_kost en tco sommeren nu ook stap4 (subtract) en
--      stap7 (add). Stap7 was returned maar niet gesommeerd — bug uit T-039.
--
-- Nieuwe totaal formule:
--   totaal = stap2 - stap3 - stap4 + stap5 + stap6 + stap7 + stap8 + stap9
--
-- Postgres kan RETURNS TABLE niet CREATE OR REPLACE-en zodra kolommen
-- toegevoegd worden -> DROP + CREATE.
--
-- Backward-compat UI: nieuwe kolom is optioneel voor bestaande consumers.
-- Numerieke output op totaal/tco verandert wel wanneer stap4 en/of stap7
-- non-zero zijn voor een tenant.
--
-- Rollback: revert naar 20260704000200_cascade_populatie_snapshot_stap8_9_mu.sql.


drop function if exists public.cascade_populatie_snapshot(date, uuid, uuid);


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
        stap4_doelgroep numeric(18, 4),
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
            coalesce(nullif(public.mu_van_prestatie(c.contract_id, p_periode), 0), 1.0000)::numeric(6, 4) as mu,
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
            coalesce(
                public.cascade_stap3_structurele_vermindering(ct.bruto * 3, ct.mu, ct.werkgeverscategorie, p_periode),
                0
            )::numeric(18, 4) as stap3_vermindering,
            -- ISS-076 fix: stap4 wordt nu aangeroepen (was skipped in T-039/T-058).
            coalesce(
                public.cascade_stap4_doelgroepverminderingen(ct.contract_id, ct.bruto, ct.mu, p_periode),
                0
            )::numeric(18, 4) as stap4_doelgroep,
            coalesce(
                public.cascade_stap5_bijzondere_bijdragen(ct.bruto, p_periode),
                0
            )::numeric(18, 4) as stap5_bijzondere,
            coalesce(
                public.cascade_stap6_vakantiegeld(ct.bruto, ct.status, p_periode),
                0
            )::numeric(18, 4) as stap6_vakantiegeld,
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
            coalesce((
                select public.cascade_stap8_wagen_solidariteitsbijdrage(fw.co2_g_km, fw.brandstoftype, p_periode)
                from public.fact_wagen fw
                where fw.contract_id = ct.contract_id
                  and fw.periode = date_trunc('month', p_periode)::date
                limit 1
            ), 0)::numeric(18, 4) as stap8_wagen,
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
        b.stap4_doelgroep,
        b.stap5_bijzondere,
        b.stap6_vakantiegeld,
        b.stap7_extralegaal,
        b.stap8_wagen,
        b.stap9_arbeidsongevallen,
        -- ISS-076 fix: volledige totaal patronale kost inclusief stap4 (subtract) en stap7 (add).
        (
            b.stap2_basis_rsz
            - b.stap3_vermindering
            - b.stap4_doelgroep
            + b.stap5_bijzondere
            + b.stap6_vakantiegeld
            + b.stap7_extralegaal
            + b.stap8_wagen
            + b.stap9_arbeidsongevallen
        )::numeric(18, 4) as totaal_patronale_kost,
        (
            b.bruto
            + b.stap2_basis_rsz
            - b.stap3_vermindering
            - b.stap4_doelgroep
            + b.stap5_bijzondere
            + b.stap6_vakantiegeld
            + b.stap7_extralegaal
            + b.stap8_wagen
            + b.stap9_arbeidsongevallen
        )::numeric(18, 4) as tco
    from berekend b;
$$;

comment on function public.cascade_populatie_snapshot(date, uuid, uuid) is
    'Populatie-snapshot: alle contracten in tenant + volledige cascade output (stap 2, 3, 4, 5, 6, 7, 8, 9) + mu per contract. RLS filtert via dim_contract / dim_legale_entiteit tenant-scoping. ISS-076 fix (2026-07-04): stap4_doelgroep column + call toegevoegd; stap4 en stap7 nu gesommeerd in totaal_patronale_kost + tco (was bug uit T-039).';

grant execute on function public.cascade_populatie_snapshot(date, uuid, uuid) to authenticated;
