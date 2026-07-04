# Autonomous Session Handover — T-016

## Delivered

**T-016 — param_structurele_vermindering + param_doelgroepvermindering** (commits `116dbf1`, `34b2f8b`)

2e parameter-laag migration in Phase 4 (na T-015). Twee tabellen met identiek T-015 exclusion+RLS+REVOKE pattern:

- `param_structurele_vermindering` (uuid PK, per werkgeverscategorie): forfait + coefficient_a + coefficient_b voor formule R = F − a·(S₀−S) − b·(S₁−S). Effective-dated met exclusion op (werkgeverscategorie, daterange).
- `param_doelgroepvermindering` (uuid PK, per gewest × doelgroep): gewest CHECK vlaanderen|wallonie|brussel (post-6e-Staatshervorming beleid per VDAB/Forem/Actiris), forfait + coefficient + voorwaarden_json jsonb NOT NULL DEFAULT '{}'. Effective-dated met exclusion op (gewest, doelgroep, daterange).
- Constitution v1.0.1: forfait numeric(18,4) beide tabellen; coefficient_a/_b + coefficient numeric(12,8) (expliciet in de precision-tabel genoemd).
- pgTAP plan(41): 9 schema shape assertions dekken alle Constitution-precision claims, 8 symmetric NOT NULL smoke incl. coefficient_a EN _b, 4 RLS + 2 REVOKE, 2 CHECK-value tests, 4 effective-dating tests, 10 exclusion tests (cross-key disambiguation + open-ended NULL + adjacency [) semantics op structurele), 2 voorwaarden_json tests incl. DEFAULT contract-verificatie.
- Manual psql smoke-verified alle key constraints (exclusion 23P01, gewest 23514, DEFAULT '{}'::jsonb behavior). npm run build exit 0.

## Beslissingen genomen

**Flow-choice clarification** (memory update)
- User bevestigde: Storybloq voor Phase 1-4 schema; speckit-flow start bij Phase 5 (rekencascade, T-026+). Vorige interpretatie "Phase 4-5 speckit" was ambigu. Memory file `feedback_phase_flow_choice.md` bijgewerkt.

**Plan review (2 rondes)**
- R1: revise (1 major R1 col_type_is undercount + 2 minor R2/R3). All folded: plan(39) → plan(41), 5 col_type_is per Constitution v1.0.1, coefficient_b NOT NULL, voorwaarden_json DEFAULT '{}' test.
- R2: approve (0 findings).

**Code review (1 ronde)**
- 3-lens verdict approve zonder findings dankzij (a) T-015 pattern precedent, (b) known false-positive lijst uit T-015 die deferred systematics dedupt, (c) verificatie dat alle plan-review fold-ins correct doorgestroomd zijn.

**Consistency choices**
- Geen land_id kolom op beide tabellen: BE-only per POC-scope, idem ISS-031 op param_rsz. Wanneer N-004 multi-country decidet, komt er 1 backfill-migratie voor de hele parameter-laag.
- `gewest` text CHECK ipv native ENUM: consistency met param_rsz.status pattern.
- `doelgroep` free-form text: catalogus evolueert bij wetgeving; enum blijft niet up-to-date zonder migration.
- `voorwaarden_json` jsonb NOT NULL DEFAULT '{}': import-scripts kunnen omitten wanneer een doelgroep geen filter-criteria heeft.

## Volgende stap voor de gebruiker

1. Vercel deploy: automatic on push (main branch).
2. `git push` om 5 commits ahead of origin te syncen (T-012 t/m T-016 tickets).
3. `supabase db push` naar hosted Supabase (T-015 + T-016 migrations).
4. ISS-030 (basejump-supabase_test_helpers extension) oplossen wanneer pgTAP CI gewenst is — blokkeert alle 25 test-files (niet T-016-specifiek).

## Volgende ticket-kandidaten

T-017 (7 tabellen: arbeidsduur, vakantiegeld, index, bijzondere_bijdragen, sectorbijdrage, extralegaal, wagen_mobiliteit) is de logische volgende — groot ticket, mogelijk splitsen. T-022 (fact tables) staat ook unblocked maar volgt logisch NA parameter-laag klaar is.

## Status

Session `7405e6af-a391-45e2-8b3d-f9ce92b91fe4` targeted work complete. 1/1 target: T-016 delivered in 2 commits + 2 plan-review + 1 code-review rondes. Branch `main` clean, 5 commits ahead van origin (T-012 t/m T-016).
