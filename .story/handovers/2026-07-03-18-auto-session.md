# Autonomous Session Handover — T-023 (uurloon_van_maandloon pure functie)

## Delivered

**T-023** (commits `b119a8d` Red, `9c9d877` Green, `9fb5c3b` metadata)

Tweede Phase 5 ticket. Pure SQL functie voor uurloon-derivation via temporele join op `param_arbeidsduur`.

### Function

```sql
public.uurloon_van_maandloon(p_maandloon numeric(18,4), p_pc_id text, p_periode date)
  returns numeric(18,4)
  language sql stable parallel safe
```

**Formule** (Belgische conventie): `uurloon = ((maandloon × 3) / (13 × gemiddelde_wekelijkse_uren))::numeric(18,4)`

Expliciete cast in body forceert 4-decimalen return (Postgres SQL functions truncate niet automatisch bij returns-declaration alleen).

**Verified manual smoke** (exact test-verwachting):
- PC 200 (38u/week) maandloon 4000 → **24.2915**
- PC 124 (40u/week bouw) maandloon 4000 → **23.0769**
- PC 200 kleine maandloon 1000 → **6.0729**
- Temporele miss (nonexistent PC) → NULL
- Cross-period miss (2023-01-01 pre-import) → NULL

### pgTAP plan(10)

has_function (1) + Sanity PC 200/124/111 (3) + Zero-maandloon edge (1) + Cross-precision small maandloon (1) + Temporele miss nonexistent (1) + Cross-period miss (1) + Determinisme × 2 (2).

Alle test-namen citeren bron per Principe V regel 170 ("Belgische conventie 13 maanden = 52 weken; RSZ instructiegids 2024/1").

## Beslissingen genomen

**Plan review (1 round → approve met 3 folds)**
- HIGH: Signature-deviation `calc_uurloon(contract_id, periode)` → `uurloon_van_maandloon(maandloon, pc_id, periode)`. ADR-sectie toegevoegd met 4 rationale-punten (Principe III purity, herbruikbaarheid, contract-artifact, naamgeving).
- MEDIUM: TypeScript-parallel implementation gedeferred naar **ISS-033** (Phase 7 UI-simulator).
- LOW: Deeltijds/tijdskrediet grensgevallen expliciet gedocumenteerd als caller-side.

**Code review (1 round → approve)**
- 1 low finding gecontest: LIMIT 1 / uniqueness guard onnodig want T-017 EXCLUDE USING gist constraint op (pc_id, daterange) garandeert MAX 1 rij per (pc_id, periode). Multi-match onmogelijk.

**Inline fixes tijdens implementation**:
- Postgres `||` string-concatenation in `COMMENT ON FUNCTION` werkt niet in oude versies — vervangen door single-line string.
- Explicit `::numeric(18,4)` cast in function-body — Postgres SQL functions truncate niet automatisch bij `returns` declaration.

**Constitution compliance**:
- Principe I: temporele join op param_arbeidsduur.geldig_van/geldig_tot
- Principe III: pure functie, geen hardcoded tarieven
- Principe IV: uses fte_breuk semantisch (uurloon = beloning). μ niet betrokken.
- Principe V: TDD 2-commit — test-commit b119a8d tijdstip EERDER dan Green commit 9c9d877

## Pre-existing issues gefiled

- **ISS-033** (low): TypeScript parallel implementation. Ticket eiste "zowel SQL als TypeScript (parallel voor UI-simulator)"; TS-kant deferred naar Phase 7 wanneer UI-consumer bestaat. Cross-implementation drift-detectie via gedeelde JSON scenario-fixture.

## Volgende stap

1. `git push` — 4 commits ahead (b119a8d, 9c9d877, 9fb5c3b).
2. `supabase db push` naar hosted voor T-023 migration.
3. **T-024 mu_van_prestatie** — volgende ticket in speckit+Storybloq combo:
   - Contract al klaar in `specs/001-rekencascade/contracts/mu_van_prestatie.md`
   - Formule: μ = Q/S waar Q = sum uren met `dim_prestatiecode.telt_voor_mu = true`, S = pc-referentie-uren × (52/12)
   - TDD 2-commit pattern hergebruiken

## Session eind status

Session `1f948f02-5ff1-4ef5-b7d6-d032e1da70dd` complete. 1/1 target: T-023 delivered in 3 commits + 1 plan-review round (3 findings gefold) + 1 code-review round (0 blocking findings). Branch `main` clean. Phase 5 speckit+Storybloq combo tweede validatie — pattern werkt.
