# Contract: `uurloon_van_maandloon`

**Status**: proposed | **Owner ticket**: T-023

## Signature

```sql
create or replace function public.uurloon_van_maandloon(
    p_maandloon numeric(18,4),
    p_pc_id text,
    p_periode date
) returns numeric(18,4)
    language sql
    stable
    parallel safe
as $$
    -- Standaard formule: uurloon = maandloon * 3 / (13 * wekelijkse_uren)
    -- Wekelijkse_uren komt uit temporele join op param_arbeidsduur.
    select
        (p_maandloon * 3::numeric(18,4))
        /
        (13::numeric(18,4) * a.gemiddelde_wekelijkse_uren)
    from public.param_arbeidsduur a
    where a.pc_id = p_pc_id
      and p_periode >= a.geldig_van
      and (a.geldig_tot is null or p_periode < a.geldig_tot);
$$;
```

## Rationale voor formule

Belgische conventie: 13 maanden gelijk aan 52 weken; uurloon = maandloon / (52/12 × wekelijkse_uren) = maandloon × 3 / (13 × wekelijkse_uren). Geldt voor voltijds én deeltijds — de wekelijkse_uren komt uit `param_arbeidsduur` voor de PC (bv. 38u voor PC 200 metaal, 40u voor PC 124 bouw).

## Constitution Principe IV compliance

**Uses `fte_breuk` semantisch, NIET μ**: uurloon normaliseert de **beloning** — het is een normalisatie van het maandloon naar per-uur voor loonkloof-vergelijkingen. Deeltijds werk kan hier ingebed zijn via `fte_breuk` op contract-niveau (caller passt `p_maandloon = brutoloon × fte_breuk` toe indien voltijds referentie gewenst is; alternatief geeft caller effective maandloon direct door).

Deze functie zelf **kent geen breuk** — die zit in de caller. Documentatie in contract-tekst maakt dat expliciet.

## Preconditions

- `p_maandloon` > 0 (CHECK).
- `p_pc_id` bestaat in `dim_pc`.
- `p_periode` voldoet maand-begin CHECK.
- `param_arbeidsduur` bevat een actieve rij voor `(p_pc_id, p_periode)` — anders NULL return (temporele join miss), wat downstream als "missing param" wordt herkend.

## Postconditions

- Return-waarde is uurloon in euro's, `numeric(18,4)` cent-precisie.
- Function is `STABLE PARALLEL SAFE`: geen zijeffecten, deterministic voor identieke DB-state.

## Foutmodes

- Als `p_maandloon <= 0`: caller-verantwoordelijkheid (function returnt onzin-waarde; upstream valideert).
- Als geen `param_arbeidsduur` match: function returnt NULL. Cascade-orchestrator moet NULL detecteren en fout gooien met bericht "missing param_arbeidsduur for pc_id=X periode=Y".

## Testbaarheid (Principe V)

pgTAP tests EERST:
- **Sanity**: uurloon voor maandloon €4.000, PC 200 (38u/week) → verwacht `(4000 × 3) / (13 × 38) = 24.29` (afgerond) — check exacte `numeric(18,4)` waarde.
- **PC 124 outlier**: zelfde maandloon voor PC 124 (40u/week) → uurloon lager: `(4000 × 3) / (13 × 40) = 23.08`.
- **Temporele lookup miss**: pc_id met geen `param_arbeidsduur` voor de periode → NULL return.
- **Deterministic**: 10 opeenvolgende calls met identieke inputs → alle 10 identiek.
- **Bron-citation in test-namen**: "Belgische conventie 13 maanden = 52 weken; RSZ instructiegids sectie X".
