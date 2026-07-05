## Wat er deze sessie gebeurd is

**Grote lijnen:** vandaag was een dag van regression hunting. Wat begon als ISS-084 onderzoek (dim_legale_entiteit lek in pgTAP test 65) onthulde dat de hele pgTAP test-suite jarenlang misleidend groen was doordat tests als postgres-superuser draaiden. Fix aligned onze `tests.authenticate_as` shim met upstream basejump (role switch). Dat exposeerde stille prod-bugs (grants weggevallen bij drop cascade in mart_loonkloof + decomp_read) én maakte ~60 bestaande tests plotseling rood (want ze testten capabilities die authenticated niet heeft).

Vervolgens deed ik een e2e walkthrough in browser die 3 aparte prod-bugs vond: RSC boundary crash op dashboard (icon functies naar client component), setup wizard 403 (dim_legale_entiteit had geen INSERT grant), en Oaxaca "URI too long" (1000 persoon_ids in URL filter). Alle drie gefixt.

Later cross-tenant UI regression check gedaan (team B account, verifieerde dat mart_loonkloof filter en middleware guard cross-tenant leakage voorkomen).

Grootste ontdekking: bij ISS-085 pilot (test 21 refactor met setup-als-postgres pattern) bleek dat migratie 20260703350000 "fix_domain_table_grants" de GDPR column-REVOKE op dim_persoon.geslacht/opleidingsniveau had ongedaan gemaakt. Sinds 2026-07-03 kon elke authenticated user in tenant direct gender + opleiding data lezen van collega's. **ISS-086 aangemaakt severity=high, opgelost via nieuwe RPC met rechtsgrondslag-audit en herstelde column-REVOKE (met correcte table-REVOKE + per-kolom GRANT pattern).**

## Prod pushes vandaag (in volgorde)

1. `063abc1` — shim role-switch + grants restore (ISS-084)
2. `2446da4` — 3 e2e-bugs (RSC boundary, setup grant, oaxaca URI)
3. `6511d38` — toast dubbel-decode fix
4. `d606f0d` — 5 cascade tests aligned (44/47/48/52/56)
5. `cbe89e2` — 3 cascade tests aligned (42/43b/57)
6. `cac8b03` — test 21 refactor pilot + ISS-086 discovery
7. `2e58883` — ISS-086 GDPR fix (RPC + column-REVOKE hersteld)

## Where to pick up

**ISS-085 is de grote open post.** 9 van ~60 tests recovered. Nog:

**Bucket A — Grants pattern (7 tests: 22-28)**  
Pilot pattern uit test 21 (setup-als-postgres, drop directe INSERT asserts, behoud RLS-read + column-REVOKE). Ongeveer 5-10 min per test. Kan meer regressies onthullen zoals ISS-086 deed.

**Bucket B — UUID-conflict (14 tests: 46, 50, en anderen)**  
Delen `a1111111-1111-1111-1111-111111111111` / `aaaaaaaa-1111-1111-1111-111111111111` met de Demo BVBA seed. Bij insert: duplicate PK. Fix: unieke test-UUIDs per test, of DELETE-first pattern. Groter refactor werk.

**Bucket C — Formule-rewrite (1 test: 45)**  
Test 45 stap 3 structurele vermindering: coefficient_b is re-purposed van δ hoog-lonen naar γ zeer-lage-lonen. Formule + expected values allemaal herschrijven volgens huidige function signature.

## Belangrijke context voor de volgende sessie

- `tests.authenticate_as` shim (migratie 20260705200000) DOET NU role switch. Vertrouw geen oude test die als postgres draaide.
- `mart_loonkloof` en `mart_loonkloof_decomp_read` grants zijn kwetsbaar voor drop-cascade — check bij elke migratie die deze objects raakt.
- ISS-086 heeft een nieuwe pattern: `get_oaxaca_persoon_opleiding` RPC met tenant-check + audit. Als vergelijkbare protected-column-access nodig is, kopieer die RPC.
- Column-REVOKE-na-table-GRANT werkt niet in Postgres. Correct pattern: table-REVOKE + per-kolom GRANT alleen niet-beschermde.
- Deze sessie deed 7 prod pushes. Volgende sessie: check `git log --oneline main --since=2026-07-06` voor eventuele externe commits.

## Nog gevonden maar niet gefixt

- **Cross-tenant leak potentie in dim_persoon**: mart_loonkloof heeft geslacht kolom leesbaar voor authenticated. Voor de POC-demo waarschijnlijk OK (aggregate access), maar prod release: overweeg mart_loonkloof access ook via RPC.
- **Test 45 fiscale semantiek**: het domain team moet uitspraak doen of coefficient_b δ hoog-lonen ↔ γ zeer-lage-lonen re-purposing intended is (docs suggereren van wel na Q3 2025 regeerakkoord). Voor test-refactor moet ik dat aannemen.
