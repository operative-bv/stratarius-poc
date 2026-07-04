# T-042 handover — cascade stap 3 structurele vermindering

## Delivered (4 commits)
- 08d31fd test Red split (43b HOTFIX + 45 function)
- 5adf948 feat Green: 2 migrations (259000 S0/S1 HOTFIX + 260000 function) + test arithmetic corrections
- 7fe7f13 docs fix: column comment operator precedence (fold code review)
- ad56116 metadata

## Function

```sql
public.cascade_stap3_structurele_vermindering(numeric, numeric, smallint, date)
  returns numeric(18,4) LANGUAGE SQL STABLE PARALLEL SAFE
  SET search_path = public, pg_temp
```

Formule (EXPLICIETE haakjes per T-026 fold):
  R = (F + α × GREATEST(0, S0-S) + δ × GREATEST(0, S-S1)) × μ

Principe IV KRITIEK: μ schaalt HELE R (niet alleen δ-term). Function accepteert p_mu, leest GEEN dim_contract.fte_breuk.

## HOTFIX (aparte migration, patroon T-041)

20260703259000: drempel_s0 + drempel_s1 numeric(18,4) NOT NULL + CHECK (s0 <= s1) + backfill 7207.20 / 12435.31 + LOCK TABLE ACCESS EXCLUSIVE transactional.

## Manual smoke (10 scenarios)

- T2 cat 1 laag S=6000: 169.0080 (0.14 × 1207.20) ✅
- T3 cat 1 deadband S=8000: 0 ✅
- T5 cat 2 laag: 49 + 318.82 = 367.8215 ✅
- T6 cat 3 laag: 375 + 206.91 = 581.9141 ✅
- T7 cat 3 hoog S=15000: 375 + 175.94 = 550.9377 ✅
- **T9 KEY Principe IV**: cat 1 S=6000 μ=0.5 → 169.0080 × 0.5 = 84.5040 (bewijst μ × HELE R via haakjes) ✅
- T10 boundary S=S0 exact: 375 ✅
- T11 boundary S=S1 exact: 375 ✅
- T12 temporele miss: NULL ✅

## Inline arithmetic corrections

Mijn plan.md verwachtte 168.9080 (was ook fout in T-026 review). Postgres: 0.14 × 1207.20 = **169.0080**. Fixed T2, T7, T9 expected values. Les: manual arithmetic in cascade-plans altijd tegen `docker exec psql` verifiëren vooraleer test-values op te schrijven.

## Fold code review round 1

1 addressed:
- Column comment op drempel_s0 miste buitenste haakjes — herintroduceerde exact de precedence bug die T-042 elimineerde. Fixed.

5 deferred (non-blocking):
- coefficient_a/b naming: schema tech-debt T-016
- Backfill literal duplication: POC-scale
- NULL mu/grondslag tests: caller-side, consistent T-023/24/26/41 contract
- Negative input tests: cascade orchestrator T-029 responsibility
- CHECK constraint negative test: DB declarative

## Volgende

1. `git push` — 4 commits ahead
2. `supabase db push`
3. Cascade stap 1-3 COMPLETE. Volgende: **T-027** (stap 4-6 doelgroepverminderingen + bijzondere bijdragen + provisies) OF **T-028** (stap 7-9 extralegaal + wagen + arbeidsongevallen). T-029 orchestrator brengt alles samen.

## Session stats

Session `9c705bc8` complete in 3 review rounds, 4 commits. Phase 5 cascade backbone (stap 1-3) nu volledig geleverd: uurloon (T-023), μ (T-024), round_final (T-025), stap 1 grondslag (T-026), stap 2 basis RSZ (T-041), stap 3 structurele vermindering (T-042).