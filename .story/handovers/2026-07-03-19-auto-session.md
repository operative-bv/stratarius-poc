# Autonomous Session Handover — T-024 (mu_van_prestatie µ = Q/S)

## Delivered

**T-024** (commits `70e209d` Red, `e4868a4` Green, `873aebe` metadata)

Derde Phase 5 ticket. Pure SQL functie voor µ = Q/S derivation — effectieve prestatiebreuk. **Kritieke Principe IV afdwinging**: leest GEEN dim_contract.fte_breuk.

### Function

```sql
public.mu_van_prestatie(p_contract_id uuid, p_periode date)
  returns numeric(6,4)
  language sql stable parallel safe
```

**Formule**:
- Q = SUM(fact_prestatie.uren) WHERE dim_prestatiecode.telt_voor_mu = true
- S = param_arbeidsduur.gemiddelde_wekelijkse_uren × (52/12)
- µ = Q / S

**Verified 6 scenarios** (manual smoke):
| Scenario | Verwacht | µ |
|---|---|---|
| T1 voltijds baseline PC 200 | 1.0000 | ✅ 1.0000 |
| T2 tijdelijke_urenvermindering filter | 0.3644 | ✅ 0.3644 |
| T4 **Principe IV bewijs** fte_breuk=0.5 maar 100u werkelijk | 0.6073 | ✅ 0.6073 |
| T5 overuren (200u) | 1.2146 | ✅ 1.2146 |
| T6 missing fact_prestatie | 0.0000 | ✅ 0.0000 |
| T7 missing param_arbeidsduur | NULL | ✅ NULL |

**pgTAP plan(9)**: has_function + 8 scenarios.

### KEY test T4: bewijs Principe IV separation

Contract C: `fte_breuk = 0.5` (deeltijds contract) MAAR 100u `normaal_gewerkt` werkelijk gepresteerd. Function returnt µ = 100 / 164.6667 = **0.6073** — NIET 0.5!

Dit bewijst dat function GEEN dim_contract.fte_breuk gebruikt. Als het dat wel deed, was mu = 0.5.

### KEY test T2: bewijs telt_voor_mu filter

60u `normaal_gewerkt` + 20u `tijdelijke_urenvermindering` (`telt_voor_mu=false` per T-013 seed).
- Zonder filter: Q = 80, µ = 80/164.6667 = 0.4858
- Met filter: Q = 60, µ = 60/164.6667 = **0.3644** ✅

## Beslissingen genomen

**Plan review (1 round → approve met 2 folds)**
- MEDIUM: prestatiecode-naam fix `normale_uren` → `normaal_gewerkt` (T-013 seed werkelijke naam)
- LOW: contract-doc fix `dp.prestatiecode_id` → `dp.prestatiecode` (dim_prestatiecode PK werkelijke naam)

**Code review (1 round → approve)**
- 2 low findings non-blocking (hotfix single-responsibility tradeoff gedocumenteerd; non-existent contract_id test kan later)

**Inline fixes tijdens implementation** (5 stuks):
- geslacht `'V'`/`'M'` → `'v'`/`'m'` (T-005 CHECK values lowercase)
- dim_persoon.owning_account_id seed toegevoegd (NOT NULL)
- dim_functie seed toegevoegd (dim_contract.functie_id NOT NULL)
- dim_contract.statuut → dim_contract.status (kolom-naam)
- **Numeric precision bug in T-022**: fact_prestatie.uren was `numeric(6,4)` (max 99.9999) — realistisch is 100-200 uren/maand. Inline hotfix `ALTER TABLE fact_prestatie ALTER COLUMN uren TYPE numeric(10,4)` toegevoegd aan T-024 migration.
- Test-verwachte waarden gerecomputed: T4 0.6072 → 0.6073 en T5 1.2145 → 1.2146 (Postgres round-half-away-from-zero op vijfde decimaal)

## Pre-existing issues gefiled

- **ISS-034** (medium): T-022 fact_prestatie.uren `numeric(6,4)` te krap. Hotfix inline in T-024 migration; volwaardige refactor bij volgende schema-cleanup.

## Volgende stap

1. `git push` — 4 commits ahead (70e209d, e4868a4, 873aebe).
2. `supabase db push` naar hosted voor T-024 migration (inclusief hotfix).
3. **T-025 round_final()** — volgende ticket:
   - Banker's rounding (round half to even) op 2 decimalen
   - Contract klaar in `specs/001-rekencascade/contracts/round_final.md`
   - TDD 2-commit pattern
   - Boundary cases (0.005 → 0.00, 0.135 → 0.14, negatief bereik) test-first

## Session eind status

Session `1297c12f-39ba-4e30-868d-b021b5a56c5c` complete. 1/1 target: T-024 delivered in 3 commits + 1 plan-review round + 1 code-review round + ISS-034 gefiled + 5 inline fixes. Branch `main` clean. Phase 5 speckit+Storybloq derde validatie. Principe IV expliciet bewezen via T4 test.