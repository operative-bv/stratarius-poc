# Autonomous Session Handover — T-022 (Phase 5 kick-off, TDD-first)

## Delivered

**T-022 — fact tables migration** (3 commits: `fd22ee3` Red, `0673ead` Green, `5cc383b` metadata)

**Phase 5 rekencascade START.** Eerste ticket met **TDD 2-commit pattern** per Constitution Principe V NON-NEGOTIABLE.

### Speckit-flow output

`specs/001-rekencascade/`:
- `spec.md` — 3 user stories, 8 edge cases, 17 FRs, 8 SCs
- `plan.md` — 5 constitution gates PASS, project structuur, TDD 2-commit workflow
- `research.md` — 5 design decisions:
  1. AFGELEID via REVOKE writes + SECURITY DEFINER function (T-027)
  2. scenario_id op fact_looncomponent + fact_loonkost; NIET op fact_prestatie/fact_wagen
  3. periode = date NOT NULL CHECK date_trunc('month', periode) = periode
  4. kostenblok CHECK IN 7 canonieke waarden
  5. 5 referentiescenarios voor T-029
- `data-model.md` — exacte kolom-specs per fact-tabel + cascade-context entity
- `contracts/` — 4 function contracts (create_loonkost_cascade, uurloon, mu, round_final) met test-first checklists
- `quickstart.md` — 7-stap runbook

### 4 fact tabellen

| Tabel | Type | scenario_id | Bijzonderheid |
|---|---|---|---|
| fact_looncomponent | input | ✅ | Cascade groepeert via dim_looncomponent gedragstags (Principe II) |
| fact_prestatie | input | ❌ | Scenario-vrij; input voor μ = Q/S (telt_voor_mu filter) |
| fact_wagen | input | ❌ | Scenario-vrij; 8-brandstof enum + CO2 range 0-500 |
| fact_loonkost | **OUTPUT AFGELEID** | ✅ | REVOKE writes; GRANT INSERT/UPDATE aan service_role |

**pgTAP `plan(41)`**: schema shape (11), NOT NULL (8 symmetric), CHECK (7 incl. maand-begin per tabel), RLS (8 incl. cross-tenant negative INSERT), AFGELEID (3), unique (2), FK (2).

### TDD-integrity bewijs

```
fd22ee3  test(cascade): fact tables pgTAP EERST — Red (T-022 Principe V)
0673ead  feat(cascade): fact tables migration — Green (T-022)
5cc383b  docs(cascade): Phase 5 speckit artifacts + T-022 finalize
```

Test-commit tijdstip **6 minuten EERDER** dan migration-commit — Principe V TDD-first bewijs. Storybloq code-review lens verified.

## Beslissingen genomen

**Plan review (1 round → approve met folds)**
- CC1 medium: plan(33) → plan(41) met symmetrisch per-tabel coverage
- SS1 medium: 3 aparte RLS policy-blokken expliciet uitgeschreven (voorkomt copy-paste tabel-naam verwisseling → tenant-lekkage)
- EE1 low: cross-tenant negative INSERT tests op input fact-tabellen

**Code review (1 round → approve 0 findings)**

**Inline fixes tijdens implementation**:
- FK `dim_prestatiecode.prestatiecode` (niet prestatiecode_id — kolom-naam mismatch)
- `GRANT INSERT, UPDATE ON fact_loonkost TO service_role` (was missing; cascade-schrijfroute matcht Decision 1)

**Speckit ÷ Storybloq scope split**:
- Speckit ownership: feature-level artifacts (spec, plan, research, data-model, contracts) blijven statisch tijdens hele Phase 5
- Storybloq ownership: per-ticket lifecycle (plan-review, code-review, commits, handovers)
- Overlap: Storybloq's per-ticket plan.md refereert naar speckit artifacts als input; overlap is proportioneel klein

## Volgende stap

1. `git push` — 3 commits ahead (fd22ee3, 0673ead, 5cc383b).
2. `supabase db push` naar hosted Supabase voor T-022 migration.
3. **T-023 uurloon_van_maandloon** — volgende ticket, pattern:
   - Storybloq PICK_TICKET T-023
   - Plan verwijst naar `specs/001-rekencascade/contracts/uurloon_van_maandloon.md` als functionele spec
   - TDD 2-commit: pgTAP `40-uurloon-function.sql` first (Red), migration `20260703210000_uurloon_function.sql` second (Green)
4. **Alle 7 remaining Phase 5 tickets** (T-023 t/m T-029) volgen zelfde pattern.

## Session eind status

Session `fcd23cd5-b0b4-4183-a827-cc078a657858` complete. 1/1 target: T-022 delivered in 3 commits + 1 plan-review round + 1 code-review round. Branch `main` clean. **Phase 5 kick-off successful; speckit-Storybloq combo pattern gevalideerd.**
