# Contract: `mu_van_prestatie`

**Status**: proposed | **Owner ticket**: T-024

## Signature

```sql
create or replace function public.mu_van_prestatie(
    p_contract_id uuid,
    p_periode date
) returns numeric(6,4)
    language sql
    stable
    parallel safe
as $$
    -- μ = Q / S waar:
    --   Q = som van gewerkte uren (fact_prestatie) waar dim_prestatiecode.telt_voor_mu = true
    --   S = referentie-uren-per-maand voor de PC van het contract
    --   S = param_arbeidsduur.gemiddelde_wekelijkse_uren × (52/12) = wekelijkse_uren × 4.333333
    with q as (
        select coalesce(sum(fp.uren), 0::numeric(6,4)) as som_uren
        from public.fact_prestatie fp
        join public.dim_prestatiecode dp on dp.prestatiecode = fp.prestatiecode_id
        where fp.contract_id = p_contract_id
          and fp.periode = p_periode
          and dp.telt_voor_mu = true
    ),
    s as (
        select a.gemiddelde_wekelijkse_uren * (52::numeric(6,4) / 12::numeric(6,4)) as ref_uren
        from public.dim_contract c
        join public.param_arbeidsduur a
            on a.pc_id = c.pc_id
           and p_periode >= a.geldig_van
           and (a.geldig_tot is null or p_periode < a.geldig_tot)
        where c.contract_id = p_contract_id
    )
    select q.som_uren / s.ref_uren from q, s;
$$;
```

## Constitution Principe IV compliance

**Uses μ (Q/S), STRIKT gescheiden van `fte_breuk`**: deze functie berekent μ = effectieve prestatiebreuk, gebruikt door pro-rata verminderingen in de cascade (structurele + doelgroep). μ ≠ fte_breuk bij tijdelijke urenvermindering (bv. tijdskrediet): contract `fte_breuk = 1` maar `mu = 0.8` als 20% minder gewerkte uren.

**Filter `telt_voor_mu = true`** is CRUCIAAL: `dim_prestatiecode.telt_voor_mu = false` voor `tijdelijke_urenvermindering` — die uren tellen NIET in Q, wat μ correct lager maakt.

## Preconditions

- `p_contract_id` bestaat in `dim_contract`.
- `p_periode` voldoet maand-begin.
- `fact_prestatie` bevat minstens één rij voor `(p_contract_id, p_periode)` — anders Q=0 → μ=0, wat downstream cascade als "geen prestaties" behandelt.
- `param_arbeidsduur` heeft actieve rij voor `(contract.pc_id, p_periode)`. Zonder → S is NULL, μ is NULL.

## Postconditions

- Return-waarde is μ in `numeric(6,4)` breuk-precisie (bereik 0.0000-9.9999).
- Voor voltijds werker met 100% prestatie: μ ≈ 1.0000 (kleine afwijkingen door 52/12 vs kalender-dagen).
- Overuren push μ boven 1.0000 — dat is bedoeld en gewenst.
- STABLE + PARALLEL SAFE.

## Foutmodes

- `param_arbeidsduur` mist → NULL return. Cascade-orchestrator detecteert NULL en gooit gestructureerde fout.
- Contract bestaat niet → SQL error op join. Ophaler moet dit vangen.

## Constitution Principe II compliance

**Filter `telt_voor_mu = true` gebruikt gedragstag, GEEN prestatiecode-ID**: nieuwe prestatiecodes (bv. `dienstwissel_binnen_team`) kunnen worden toegevoegd met correcte `telt_voor_mu` waarde — geen wijziging aan deze function nodig.

## Testbaarheid (Principe V)

pgTAP tests EERST:
- **Voltijds baseline**: contract PC 200, 164u gewerkt in maand (=38×52/12=164.67), verwachte μ ≈ 1.0000.
- **Tijdelijke urenvermindering**: contract met 40u prestatie `normaal_gewerkt` + 20u prestatie `tijdelijke_urenvermindering` in dezelfde maand → Q = 40u (niet 60u!) → μ ≈ 0.2440 (40 / 164.67). Bewijst dat `telt_voor_mu` filter werkt.
- **Overuren**: 200u prestatie in maand van 164.67 ref-uren → μ ≈ 1.2145 > 1. Constitution Principe IV toestaat overuren via μ > 1.
- **PC 124 outlier**: zelfde 164u prestatie voor PC 124 (40u/week = 173.33 ref-uren) → μ ≈ 0.9462 < 1.
- **fte_breuk vs μ**: contract met `fte_breuk = 0.5` (deeltijds) MAAR 100u werkelijke prestatie → μ = 100 / 164.67 ≈ 0.6072 (NIET 0.5). Bewijst dat function μ berekent, niet fte_breuk gebruikt.
- **Determinisme**: 10 opeenvolgende calls identiek.
