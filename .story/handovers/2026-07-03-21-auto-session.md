# Autonomous Session Handover — T-026 (cascade stap 1 rsz_grondslag, scope-reduced)

## Delivered

**T-026** (commits `3cb28bf` Red, `05e422c` Green, `3993349` perf fold, `0f3fbf8` metadata)

Eerste cascade-functie geleverd. Scope reduced tijdens plan-review — origineel was stap 1-3 in één ticket, herscoped naar stap 1 only na 4 critical blockers uit 3-lens review + user consult.

### Function

```sql
public.cascade_stap1_rsz_grondslag(p_contract_id uuid, p_periode date, p_scenario_id uuid)
  returns numeric(18, 4)
  language sql stable parallel safe
  set search_path = public, pg_temp
```

**Formule**:
- som_rsz_plichtige = SUM(fact_looncomponent.bedrag) WHERE dim_looncomponent.rsz_plichtig = true
- maandloon = SUM(fact_looncomponent.bedrag) WHERE dim_looncomponent.is_basisloon = true (NIEUWE gedragstag via HOTFIX)
- uurloon = T-023 uurloon_van_maandloon(maandloon, contract.pc_id, periode)
- overloon = SUM(fp.uren × uurloon × dp.toeslag_pct) WHERE dp.toeslag_pct IS NOT NULL
- RSZ_grondslag = som_rsz_plichtige + overloon

**NULL propagation** via had_rows + bedrag pattern in overloon CTE: onderscheidt "geen overuren" (COALESCE 0) van "overuren aanwezig maar uurloon niet te berekenen" (propageer NULL).

**Verified alle 7 scenarios** (manual smoke via docker psql):
- T3 basisloon 4000 → 4000.0000 ✅
- T4 basisloon + premie → 4100.0000 ✅
- T5 basisloon + VAA → 4000.0000 (VAA gefilterd via rsz_plichtig; Principe II bewijs) ✅
- T7 missing fact → 0.0000 (COALESCE) ✅
- T8 basisloon + 10u overuren_50 × 24.2915 × 0.50 → 4121.4575 ✅
- T10 alleen overuren zonder basisloon → 0.0000 (maandloon=0 → uurloon=0) ✅
- T11 overuren + missing param_arbeidsduur → NULL (had_rows propageert) ✅

pgTAP plan(12) lokaal geblokt door ISS-030.

## Beslissingen genomen

### Scope reductie (plan-review round 1)

3 lenses (clean-code, security, error-handling) convergeerden op 4 critical blockers:
1. Arithmetic error in plan T-20: 168.9880 vs correct 168.9080
2. Operator precedence: `F + α×max(0,S0-S) + δ×max(0,S-S1) × μ` — zonder haakjes alleen δ-term × μ
3. Migration bundling: schema HOTFIX (S0/S1 columns) + 3 function migrations
4. Unresolved design: "wat is basisloon voor overloon-uurloon" (Principe II inbreuk risk)

User consulted → scope reduced. Stap 2 verplaatst naar **T-041**, stap 3 (met S0/S1 hotfix + boundary tests + expliciete haakjes + μ validation) verplaatst naar **T-042**.

### is_basisloon gedragstag HOTFIX

Voor Principe II-conforme overloon-uurloon berekening: nieuwe boolean tag op dim_looncomponent. Alleen 'basisloon' component gezet op true. Nieuwe basisloon-varianten moeten expliciet gezet worden (audit via ISS-045).

### FILTER-fold code review

Code-review performance lens MAJOR + clean-code lens MINOR converged: 2 CTEs deden identieke JOIN op fact_looncomponent. Fold naar één 'lonen' CTE met SUM(...) FILTER (WHERE ...). Halveert I/O op cascade schaal.

## Inline fixes

1. Prestatiecode `overuren_50pct` fout naam → correct `overuren_50` per T-013 seed.
2. dim_scenario schema fout: `owning_account_id` + `is_baseline` → correct `legale_entiteit_id` + `kind`.
3. NULL propagation bug in eerste implementatie: COALESCE(0) in overloon SUM até de NULL signal. Fixed via had_rows + bedrag pattern.
4. Post-code-review FILTER refactor: 2 CTEs → 1 CTE met FILTER clauses.

## Pre-existing issues gefiled

- **ISS-042** (medium): T-029 orchestrator N+1 pattern — batch-variant `cascade_stap1_rsz_grondslag_batch(periode, scenario) RETURNS TABLE(contract_id, grondslag)` aanbevolen voor productie-schaal.
- **ISS-045** (medium): is_basisloon seed audit follow-up — nieuwe basisloon-varianten moeten expliciet is_basisloon=true krijgen.

## Nieuwe tickets aangemaakt

- **T-041**: Cascade stap 2 basis patronale RSZ (grondslag × tarief × arbeider-factor). Fold-in: seed basisfactor_arbeider_pct = 1.0000 voor bediende ipv coalesce, add SET search_path.
- **T-042**: Cascade stap 3 structurele vermindering met S0/S1 HOTFIX als aparte migration, boundary tests S=S0 exact + S=S1 exact, expliciete `(F + ... + ...) × μ` haakjes, μ ∈ [0,1] validation.

## Volgende stap

1. `git push` — 4 commits ahead (3cb28bf, 05e422c, 3993349, 0f3fbf8).
2. `supabase db push`.
3. **T-041** — volgende Phase 5 ticket: cascade stap 2 basis patronale RSZ. Klein en focused per T-026 lessons.

## Session eind status

Session `bc69540b-4df2-4753-ae30-6c2fcd435f34` complete. 1/1 target: T-026 delivered in 4 commits + 1 plan-review round (scope reduction + 4 major folds) + 1 code-review round (2 findings applied inline) + 2 issues gefiled + 2 nieuwe tickets aangemaakt. Branch `main` clean. Phase 5 vierde functie geleverd (T-023 uurloon, T-024 μ, T-025 round_final, T-026 stap 1). Cascade architectuur werkelijk begonnen te leveren.

**Key lesson**: origineel T-026 was te groot voor één ticket. Plan-review lens system detecteerde dit voordat ineffective implementation begon. Scope-reduction proces (user consult + ticket split) is nu bewezen patroon voor toekomstige oversized tickets.