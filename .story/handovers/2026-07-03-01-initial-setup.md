# Initial setup — Stratarius roadmap ratified

**Date**: 2026-07-03
**Session type**: setup + roadmap ratification (no code changes)

## Wat is er gebeurd deze sessie

Van null naar volledig scaffolded Spec-Driven + tracked project op één sessie:

1. **Spec Kit initialized** (`specify init --here --integration claude`) — `.specify/` + `.claude/skills/speckit-*/`.
2. **Constitution v1.0.0 geratificeerd** met 5 principes (I effective-dating, II data-driven behavior, III strict separation, IV two fractions never conflated, V test-first cascade) + Schema Naming Conventions sectie + Domain/Compliance sectie + Workflow Gates.
3. **Git repo geïnitialiseerd** + eerste commit (`81c207e`) met Basejump baseline + Spec Kit scaffolding + constitution.
4. **Storybloq initialized** (`storybloq_init`) — `.story/` scaffold + quality pipeline geconfigureerd (WRITE_TESTS + TEST + VERIFY + BUILD per Principe V).
5. **7 phases + 38 tickets aangemaakt** met beschrijvingen + blockedBy dependencies + 9 notes voor undecided decisions.

## Belangrijke setup-decisions (gate-per-gate)

- **Project type**: npm / TypeScript. Basejump (Next.js 14 App Router + Supabase) is de baseline; alle Basejump-tables (accounts, invitations, billing) blijven ongewijzigd.
- **Domein**: Belgisch werkgeverskost-berekening (loonkost, TCO, loonkloof). Ref: `_supporting-material/Datamodel_werkgeverskost_Belgie.pdf` (9 pagina's, 4 lagen, 9-stappen cascade).
- **Systeem-shape**: Frontend + managed backend (Supabase BaaS). Basejump multi-tenant model behouden.
- **Auth**: Basejump team accounts (personal accounts vermoedelijk uit — decision N-007 pending).
- **AI-first**: nee, geen LLM-integraties.
- **Sensitive domain**: JA — GDPR + financiële compliance. Persoon-attributen (geslacht, geboortedatum, opleidingsniveau) STRIKT gescheiden van contract per Principe IV; audit-log verplicht voor loonkloof-toegang (T-034).
- **Quality checks**: Full pipeline — WRITE_TESTS + TEST + VERIFY + BUILD allemaal enabled. Principe V eist test-first voor rekencascade.
- **Deployment**: Vercel EU + Supabase managed EU assumption (N-009 pending). GDPR data-residency-eis.

## Naming convention (Constitution-vastgelegd)

- Narratief: Nederlands.
- Domein-schema: Nederlands lowercase snake_case (`dim_persoon`, `fact_looncomponent`, `param_doelgroepvermindering`, `geldig_van`, `fte_breuk`, `sz_behandeling_id`).
- Infrastructuur-schema: Engels (Basejump `accounts`, `invitations`, `billing_*` blijven).
- Belgische regulatory acroniemen: canoniek behouden (`rsz`, `pc`, `kbo`, `bv`, `riziv`, `rva`, `vte`, `fod`, `cao`, `sz`, `vaa`, `fso`, `bev`).

## Roadmap structuur

7 phases + 38 tickets:

| # | Phase | Ticket range | Focus |
|---|---|---|---|
| 1 | foundation | T-001..T-003 | Basejump baseline consolidatie |
| 2 | schema-ruggengraat | T-004..T-009 | Laag 1: persoon, contract, hiërarchie |
| 3 | schema-componenten | T-010..T-014 | Laag 2: componenten met gedragstags |
| 4 | parameter-layer | T-015..T-021 | Laag 3: effective-dated params + imports |
| 5 | calculation-cascade | T-022..T-029 | Laag 4: 9-stappen cascade + uurloon/μ/rounding |
| 6 | loonkloof-mart | T-030..T-034 | mart_loonkloof + OLS/Oaxaca + GDPR-audit |
| 7 | simulator-ui | T-035..T-038 | Enkelvoudige contract-simulator MVP |

Populatie-UI (bulk imports, dashboards, PDF exports, forecast-scenario UI) is expliciet future phase — komt na simulator-ui MVP.

## Reviewer-bevindingen die de roadmap materieel veranderden

Onafhankelijke Claude agent audit vond 9 categorieën gaten. Belangrijke fixes:
- **`dim_pc` (paritair comité)** was compleet vergeten — nu T-007, feeds contract/param_arbeidsduur/param_sectorbijdrage/map_entiteit_pc_competentie.
- **Uurloon-derivation én μ-derivation** waren impliciet in cascade stap 1 — nu eigen tickets (T-023, T-024) omdat ze meerdere consumers voeden.
- **Rounding-policy** miste — nu T-025 `round_final()` als enige afrondingslocatie.
- **Named hierarchy views** (statutair/business/geografisch/kostenplaats) uit PDF Laag 1 waren niet getickett — nu T-009.
- **GDPR-audit-log** dekte alleen `dim_persoon`, niet `mart_loonkloof` (die geslacht inbakt) — T-034 uitgebreid om beide te dekken.
- **T-020 language fix**: cap voor Gunstregime moet via param_plafond FK, nooit als attribuut op dim_sz_behandeling (Principe III).
- **T-026 language fix**: "reads param_rsz keyed on (status, categorie, periode)" i.p.v. "per werkgeverscat 1/2/3" — Principe II expliciet.
- **T-021 param snapshot audit** uitgebreid met reconciliation tests + bron_url NOT NULL invariants.
- **T-015 param_rsz + param_plafond** uitgebreid met exclusion constraint tegen overlappende tijdvakken (Principe I).

## 9 undecided decisions (notes N-001..N-009)

Alle als notes gecreëerd met tag `decision-pending`. Kritische paden:

| Note | Decision | Blokkeert |
|---|---|---|
| N-001 | Legal source-acquisition (scrape vs vendor) | T-018/T-019/T-020 |
| N-002 | Parameter-freshness SLA | T-021 |
| N-003 | Non-money numeric precision | T-006, T-022+ |
| N-004 | Historische parameter-data volume (2015? 2020? 2024?) | T-018/T-019/T-020 |
| N-005 | Basejump Stripe billing scope | Phase 1 |
| N-006 | UI language | T-035..T-038 |
| N-007 | Basejump personal_account voor tenant workspaces | T-005 |
| N-008 | OLS/Oaxaca tooling | T-033 |
| N-009 | Deployment target (bevestigen Vercel EU + Supabase EU) | Phase 1 |

Aanbevolen POC-defaults zijn per note gegeven; expliciete beslissing vereist voor de tickets die eraan hangen.

## Next actions voor volgende sessie

1. **N-005 + N-007 beslissen** (Basejump billing scope + personal_account) — nodig voor T-002 scope + T-005 tenant model.
2. **N-003 beslissen** (numeric precision policy) — Constitution PATCH-bump als aanbevolen policy wordt aangenomen.
3. **T-001** (proxy.ts / middleware.ts consolideer) — kleine, zelfstandige refactor, goede warm-up.
4. **T-002** (Basejump demo cleanup) — parallelizeerbaar met T-001.
5. **T-003** (.env.example completeness) — kan gelijk.

Foundation phase compleet maken vóór schema-ruggengraat begint.

## Files & commits deze sessie

- Initial commit `81c207e`: Basejump baseline + Spec Kit + constitution.
- Volgende commit (deze handover): storybloq scaffolding + roadmap + handover + .gitignore update.

## Constitution status

v1.0.0 geratificeerd. Volgende amendment-triggers:
- N-003 aanname → PATCH bump (Schema Naming Reference precisie-appendix).
- Populatie-UI in scope → mogelijk MINOR bump als nieuwe scoping-principes nodig zijn.
- Netto-loonberekening in scope → MINOR bump (uitbreiding scope-grens).
