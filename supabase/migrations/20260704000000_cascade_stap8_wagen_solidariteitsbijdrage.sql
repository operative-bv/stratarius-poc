-- ================================================================
-- T-048: cascade_stap8_wagen_solidariteitsbijdrage pure functie
-- ================================================================
--
-- Constitution Principe III: pure SQL functie in de rekencascade. Berekent
-- de CO2-solidariteitsbijdrage (patronale RSZ per bedrijfswagen) via
-- temporele join op param_wagen_mobiliteit.
--
-- NOTE terminologie: dit is de SOLIDARITEITSBIJDRAGE die de werkgever aan RSZ
-- betaalt (Belgisch KB 20/12/2007). NIET de VAA (fiscaal voordeel werknemer,
-- staat in de simulator page.tsx als client-side berekening) en NIET de lease-
-- of aankoopkost (die zit als bedrijfswagen_tco component).
--
-- Principe II data-driven: factor + correcties + indexatie uit
--   co2_formule_json (Principe II open-ended parametrisatie). GEEN hardcoded
--   9.0 factor of 768/600/990 correcties in function-body.
--
-- Principe I effective-dating: temporele join met half-open interval
--   [geldig_van, geldig_tot) — geldig_van inclusief, geldig_tot exclusief.
--
-- Principe V TDD 2-commit: test-commit (51-cascade-stap8-wagen-...) is EERDER
-- dan deze migration.
--
-- Formule per RSZ 2024/1:
--   maandbedrag = max(minimumbijdrage,
--                     ((co2 * factor) - correctie_per_brandstoftype) * indexatie / 12)
--
-- Brandstoftype-mapping voor correctie-key:
--   benzine, hybride_benzine → 'correctie_benzine' (768.0 in 2024)
--   diesel,  hybride_diesel  → 'correctie_diesel'  (600.0 in 2024)
--   lpg                       → 'correctie_lpg'     (990.0 in 2024)
--   elektrisch, waterstof, cng → NULL correctie → return minimum
--
-- Indexatie-key is 'indexatie_YYYY' waar YYYY = jaar van p_periode.
-- Voor 2024: indexatie_2024 = 1.5359. Rijen voor 2025+ moeten indexatie_2025 etc.
-- hebben. Ontbrekend → return NULL (temporele miss-achtige semantiek).
--
-- NULL contract (consistent met T-041, T-042):
--   Temporele join miss (onbekende periode) → NULL.
--   Cascade orchestrator (T-029) detecteert NULL en throwt gestructureerde fout.
--
-- Rollback:
--   DROP FUNCTION public.cascade_stap8_wagen_solidariteitsbijdrage(smallint, text, date);


create or replace function public.cascade_stap8_wagen_solidariteitsbijdrage(
    p_co2           smallint,
    p_brandstoftype text,
    p_periode       date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    with param as (
        select
            pwm.minimumbijdrage,
            pwm.co2_formule_json
        from public.param_wagen_mobiliteit pwm
        where p_periode >= pwm.geldig_van
          and (pwm.geldig_tot is null or p_periode < pwm.geldig_tot)
        limit 1
    ),
    resolved as (
        select
            p.minimumbijdrage,
            case p_brandstoftype
                when 'benzine'         then (p.co2_formule_json ->> 'correctie_benzine')::numeric
                when 'hybride_benzine' then (p.co2_formule_json ->> 'correctie_benzine')::numeric
                when 'diesel'          then (p.co2_formule_json ->> 'correctie_diesel')::numeric
                when 'hybride_diesel'  then (p.co2_formule_json ->> 'correctie_diesel')::numeric
                when 'lpg'             then (p.co2_formule_json ->> 'correctie_lpg')::numeric
                else null
            end as correctie,
            (p.co2_formule_json ->> 'factor')::numeric as factor,
            (p.co2_formule_json ->> ('indexatie_' || extract(year from p_periode)::text))::numeric as indexatie
        from param p
    )
    select
        case
            when correctie is null then minimumbijdrage
            when factor is null or indexatie is null then null
            else greatest(
                minimumbijdrage,
                ((p_co2 * factor - correctie) * indexatie / 12)::numeric(18, 4)
            )
        end::numeric(18, 4)
    from resolved;
$$;

comment on function public.cascade_stap8_wagen_solidariteitsbijdrage(smallint, text, date) is
    'Cascade stap 8: CO2-solidariteitsbijdrage patronale RSZ per bedrijfswagen. Formule max(minimumbijdrage, ((co2*factor)-correctie)*indexatie/12) met factor+correcties+indexatie data-driven uit co2_formule_json (Principe II). Correctie per brandstoftype: benzine/hybride_benzine gebruikt correctie_benzine, diesel/hybride_diesel gebruikt correctie_diesel, lpg eigen; elektrisch/waterstof/cng -> minimum only. Principe I half-open interval [geldig_van, geldig_tot). NULL contract: temporele miss -> NULL (orchestrator T-029 detecteert). LANGUAGE SQL STABLE PARALLEL SAFE met pinned search_path.';

grant execute on function public.cascade_stap8_wagen_solidariteitsbijdrage(smallint, text, date) to authenticated;
