# T-041 handover — cascade stap 2 basis patronale RSZ

## Delivered (5 commits)
- 2d280e2 test Red split (43a plan(2) HOTFIX + 44 plan(11) function)
- 94145a9 feat Green split migrations (249000 HOTFIX + 250000 function)
- 3db6927 test fold (drop T8 dup, add S3 backfill volledigheid)
- 2697706 metadata

## Function

```sql
public.cascade_stap2_basis_patronale_rsz(numeric(18,4), text, smallint, date)
  returns numeric(18,4)
  language sql stable parallel safe
  set search_path = public, pg_temp
```

Formule: `grondslag × basisbijdrage_pct × basisfactor_arbeider_pct` via temporele join op param_rsz met half-open interval [geldig_van, geldig_tot).

## HOTFIX (aparte migration, fold plan-review MAJOR separation-of-concerns)

`20260703249000_param_rsz_basisfactor_notnull.sql`:
- LOCK TABLE ACCESS EXCLUSIVE (fold TOCTOU security)
- DROP constraint param_rsz_check1 (bevestigde naam via pg_constraint)
- UPDATE bediende: null → 1.0000 (by-convention multiply-by-one)
- ALTER SET NOT NULL
- Verbatim rollback in header

## Fold plan-review round 1 (2 rounds)

5 addressed + 1 contested:
- Migration split (2 files) ✅
- Constraint naam bevestigd (param_rsz_check1) ✅
- Boundary tests toegevoegd (UPPER-1 inclusief, UPPER exclusief) ✅
- LOCK TABLE TOCTOU safety ✅
- Verbatim rollback SQL ✅
- Silent NULL contract behouden (contested — consistent met T-023/24/26) 🔹

## Fold code-review round 1

- T8 byte-identical aan T2 dropped (plan 11→10)
- 43a S3 count-based backfill volledigheid over cat 1/2/3
- ISS-046 filed voor kolom-rename basisfactor_arbeider_pct → basisfactor_pct

## Manual smoke (docker psql)

- T2 bediende cat 1: 4000 × 0.2507 × 1.0 = 1002.8000 ✅
- T5 KEY arbeider basisfactor: 4000 × 0.2507 × 1.08 = 1083.0240 ✅
- T8 UPPER-1 inclusief (2024-12-31): 1002.8000 ✅
- T9 UPPER exclusief (2025-01-01): NULL ✅
- T10 miss vroeger (2023-01-01): NULL ✅
- Grant authenticated: true ✅

## Volgende

1. `git push` — 5 commits ahead
2. `supabase db push`
3. Volgende ticket keuze: **T-042** (stap 3 structurele vermindering met S0/S1 hotfix) OF **T-027** (stap 4-6 doelgroepverminderingen). T-042 heeft bekende voorbereiding (fold notes uit T-026 review); T-027 is nieuw domein (gewest-specifiek). Aanbeveling: T-042 om cascade linear te vervolgen.