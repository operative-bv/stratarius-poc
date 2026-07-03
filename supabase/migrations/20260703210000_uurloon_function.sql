-- ================================================================
-- T-023: uurloon_van_maandloon pure functie
-- ================================================================
--
-- Belgische conventie (PDF Laag 3 methodologie):
--   uurloon = (maandloon × 3) / (13 × gemiddelde_wekelijkse_uren)
--
-- Rationale: 13 maanden gelijk aan 52 weken; uurloon = maandloon / (52/12 × wekelijkse_uren)
-- vereenvoudigd tot maandloon × 3 / (13 × wekelijkse_uren). Geldt voor voltijds én deeltijds;
-- de gemiddelde_wekelijkse_uren komt uit param_arbeidsduur voor de PC (bv. 38u voor PC 200,
-- 40u voor PC 124 bouw).
--
-- Principe I (effective-dating): temporele join op param_arbeidsduur.geldig_van/geldig_tot
--   met daterange containment. Geen andere lookup-strategie.
--
-- Principe III (strict separation): pure functie — geen zij-effecten. LANGUAGE SQL, STABLE,
--   PARALLEL SAFE. Alle numerieke waarden uit param-laag; geen hardcoded tarieven.
--
-- Principe IV (two fractions): function gebruikt fte_breuk SEMANTISCH (uurloon normaliseert
--   BELONING). μ is NIET betrokken hier. Deeltijds/tijdskrediet grensgevallen zitten
--   CALLER-SIDE (fte_breuk in dim_contract, μ via T-024 mu_van_prestatie).
--
-- Principe V: TDD 2-commit pattern — test-commit b119a8d (40-uurloon-function.sql plan(10))
--   is EERDER dan deze migration commit.
--
-- Afwijking van ticket-description (calc_uurloon(contract_id, periode)):
--   Ticket vraagt om context-afhankelijke function (contract → maandloon lookup).
--   Deze implementatie kiest voor pure vorm uurloon_van_maandloon(maandloon, pc_id, periode)
--   omdat dat STABLE/PARALLEL SAFE mogelijk maakt en herbruikbaar is voor cascade +
--   loonkloof-normalisatie + what-if simulatie. Zie specs/001-rekencascade/plan.md
--   "Afwijking van ticket-description (ADR)" sectie.
--
-- TypeScript-parallel implementatie gedeferred naar ISS-033 (Phase 7 UI-simulator).


create or replace function public.uurloon_van_maandloon(
    p_maandloon numeric(18, 4),
    p_pc_id text,
    p_periode date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
as $$
    select (
        (p_maandloon * 3::numeric(18, 4))
      / (13::numeric(18, 4) * a.gemiddelde_wekelijkse_uren)
    )::numeric(18, 4)
    from public.param_arbeidsduur a
    where a.pc_id = p_pc_id
      and p_periode >= a.geldig_van
      and (a.geldig_tot is null or p_periode < a.geldig_tot);
$$;

comment on function public.uurloon_van_maandloon(numeric, text, date) is
    'Pure functie: uurloon = (maandloon x 3) / (13 x gemiddelde_wekelijkse_uren). Temporele join op param_arbeidsduur (pc_id, periode). Uses fte_breuk semantisch (uurloon normaliseert BELONING, Principe IV) - mu niet betrokken. Deeltijds/tijdskrediet zit CALLER-SIDE. NULL return bij temporele lookup miss; caller detecteert.';

-- GRANT EXECUTE aan authenticated: function is read-only op parameter-laag (die zelf
-- role-scoped is via T-015+ RLS `to authenticated using (true)`). Geen SECURITY DEFINER nodig.
grant execute on function public.uurloon_van_maandloon(numeric, text, date) to authenticated;
