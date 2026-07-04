# Autonomous Session Handover — T-012 + T-015

## Delivered

**T-012 — Seed dim_looncomponent** (commit `7abd509`)
- 12 canonieke Belgische loonvormen ge-seeded per PDF Laag 2
- VAA-valkuil expliciet gedemonstreerd: `bedrijfswagen_vaa` (is_werkgeverskost=false, fiscale waardering) vs `bedrijfswagen_tco` (is_werkgeverskost=true, echte kost) vs `co2_solidariteitsbijdrage` (vin_bijzondere_formule)
- Principe II negative test: familie=bedrijfswagen heeft 2 verschillende is_werkgeverskost waarden (bewijst behavior-as-data, niet name-as-behavior)
- pgTAP: 9 assertions incl. FK-integriteit tegen dim_sz_behandeling

**T-015 — param_rsz + param_plafond effective-dated parameter layer** (commits `e3ebc2d`, `142e12a`, `8e730bf`)
- btree_gist extension + 2 tabellen met exclusion constraints op DB-niveau (Constitution Principe I harde afdwinging)
- `param_plafond` (text PK regex-guarded, effective-dated met (land_id, bijdragetype, daterange) exclusion) + `param_rsz` (uuid PK, biconditional CHECK op (status, basisfactor_arbeider_pct), effective-dated met (status, werkgeverscategorie, daterange) exclusion)
- T-010 forward-reference voldaan: ALTER TABLE dim_sz_behandeling ADD CONSTRAINT dim_sz_behandeling_cap_fk
- pgTAP plan(40) — schema shape (incl. col_type_is voor alle 4 numeric-precision claims), NOT NULL smoke, RLS role-scoped read (authenticated + anon block), REVOKE writes, biconditional (2 failure + 2 success), effective-dating CHECK (3), text PK regex, exclusion (open-ended NULL overlap, cross-column disambiguation op beide tabellen, adjacency `[)` semantics), FK positive + negative + invariant
- Manual psql smoke-verified alle kritische constraints (Docker was down initially, ging up mid-session)

## Beslissingen genomen

**Plan review (2 rondes)**
- Round 1: revise (7 major test-coverage findings E1-E7 folded in)
- Round 2: approve (0 findings)

**Code review (2 rondes)**
- Round 1: 20 findings across clean-code (5) + security (2) + error-handling (6). 1 contested-major (EE1 param_rsz mist land_id → ISS-031 gedefereerd per BE-only-POC-scope + N-004 undecided). 2 cheap wins folded (EE2 col_type_is gaps + EE5 open-ended param_rsz overlap). 6 findings gedefereerd (CC1/CC3/SS2/EE3/EE4/EE6).
- Round 2 (na fix): approve (0 findings)

**Numeric precision beleid gehandhaafd**
- money → numeric(18,4) (jaarplafond, kwartaalplafond)
- rates/factors → numeric(6,4) (basisbijdrage_pct, basisfactor_arbeider_pct)
- Constitution v1.0.1 conformance nu gedekt door pgTAP col_type_is voor alle 4 kolommen

**RLS pattern verbeterd**
- Nieuwe param_* tabellen: `for select to authenticated using (true)` + REVOKE writes
- Precedent dim_sz_behandeling gebruikt `for select using (true)` (breder) — inconsistentie genoteerd als deferred SS2 voor future follow-up

## Pre-existing issues gefiled

- **ISS-030** (medium): `basejump-supabase_test_helpers` extension ontbreekt in lokale Postgres image. Alle 25 pgTAP tests falen lokaal met `extension is not available`. Niet T-015-specifiek; verify path is manual psql smoke via docker exec. Fix vereist config.toml aanpassing of migration die dbdev/extension installeert.
- **ISS-031** (low): `param_rsz` heeft geen `land_id` kolom — asymmetric met `param_plafond`. BE-only per POC-scope + N-004 undecided; blokkeert future multi-country expansion. Deferred tot N-004 resolution.

## Volgende stap voor de gebruiker

1. **Push migrations naar hosted Supabase**: `supabase db push` (user genoemd dat dit nog moet gebeuren)
2. **Push commits naar GitHub**: `git push` — 3 nieuwe commits sinds `7abd509` (`e3ebc2d`, `142e12a`, `8e730bf`)
3. **Vercel deploy**: automatic on push (main branch auto-deploys)
4. **ISS-030 oplossen** wanneer pgTAP CI weer gewenst is

## Volgende ticket-kandidaten

Phase 4 parameterlaag verder: T-016 (param_index), T-017 (param_bijzondere_bijdragen), T-018 (import scripts voor RSZ tarieven + CAO 90 plafond seed). Speckit-flow schakelt in vanaf rekencascade (T-026+) volgens de user's eerdere richting.

## Status

Session `9e129733-3b31-4e02-8cfd-7998301c79b2` targeted work complete. 2/2 targets: T-012 (delivered pre-session), T-015 (delivered this session in 2 plan-review rounds + 2 code-review rounds). Branch `main` clean, 3 commits ahead of origin.
