Sessie 2026-07-04 (2/2): Laag 4b cascade productie-completion.

## Wat is er gebeurd

Vervolg op de tracker-triage sessie eerder vandaag. Doel: cascade richting productie brengen. 6 tickets + 1 bug afgerond in Laag 4b, allemaal in strict Red→Green pattern (14 commits, 7 test-first pairs, alle 8 pgTAP-suites lokaal groen via bypass).

## Wat er is geland

**Cascade-completion (T-048, T-049, T-058):**
- T-048: `cascade_stap8_wagen_solidariteitsbijdrage` — CO2-solidariteitsbijdrage patronale RSZ per bedrijfswagen. Data-driven via co2_formule_json (factor, correcties per brandstoftype, indexatie). NIET VAA of lease.
- T-049: `param_arbeidsongevallen` tabel + `cascade_stap9_arbeidsongevallen`. POC-tarieven per PC (200: 0.30%, 302: 0.60%), min_premie 60/jaar. POC_UNVERIFIED — Fedris check nodig.
- T-058: `cascade_populatie_snapshot` uitgebreid met stap 8 + stap 9 + mu-per-contract via `mu_van_prestatie` (was hardcoded 1.0000, Principe IV violation).

**Domain-productie (T-045, T-047):**
- T-045: `cascade_stap4_doelgroepverminderingen` non-cumulatie via `voorwaarden_json.cumulatie_groep` extension. Rows in zelfde groep: hoogste bijdrage wint (beneficial-to-employer). Rows zonder groep: eigen bucket (backward compat). Design: optie B (json-extension) ipv optie A (dim_doelgroep_cumulatie tabel) om O(n) vs O(n²) en locality.
- T-047: `param_eindejaarspremie` tabel + `cascade_stap6b_eindejaarspremie`. POC coefficient-based (bruto × coefficient / 12); gelijkstellingen (uren-based via fact_prestatie) is aparte follow-up.

**Bijzondere bijdragen productie (T-046):**
- Nieuwe `cascade_stap5_bijzondere_bijdragen_productie(contract_id, bruto, periode)` met formule_json.toepassing evaluatie ("wg >= N wn" regex-parsed) + centenindex (0.5 × indexbesparing boven drempel_bruto). Oude cascade_stap5 (bruto, periode) blijft bestaan voor simulator page.tsx.

**ISS-076 fix (populatie compleetheid):**
- `cascade_populatie_snapshot` roept nu ook cascade_stap4 aan (nieuwe kolom stap4_doelgroep). totaal_patronale_kost en tco sommeren nu ook stap4 (subtract) en stap7 (add — pre-existing bug uit T-039 dat stap7 wel returned maar niet in totaal zat). TCO-cijfers in /populatie kloppen nu structureel.

## Delta metrics

- Tickets: 50/58 complete (was 44/44 aan start van dag, +14 nieuwe tickets in Laag 4b + tracker-triage)
- Issues: 13 open (was 74 aan start van dag, na tracker-triage 13 stabiel)
- 3 nieuwe param-tabellen geregistreerd: `param_arbeidsongevallen`, `param_eindejaarspremie` (arbeidsongevallen: 12 → 13 tabellen in create_parameter_snapshot v_tables)
- 4 lessons in play (L-001..L-004 uit tracker-triage sessie)

## Niet gedaan / expliciet skipped

- Populatie-snapshot integratie voor T-046 productie-versie + T-047 eindejaarspremie: geen 5e DROP+CREATE FUNCTION vandaag. Verdient een consolidatie-migration in volgende sessie.
- ISS-030 (basejump-supabase_test_helpers extension ontbreekt lokaal): nog steeds actief. `supabase test db` faalt systemisch voor alle 46+ test-files. Sessie gebruikte sed-bypass (`create extension if not exists pgtap`). Fix zou dev-loop dramatisch versoepelen.
- Auto-populatie tests in het T-058/T-045/T-046 test-files zijn beperkt tot signature checks + smoke tests, want geen tenant setup mogelijk zonder basejump helpers.

## Open bij Laag 4b (8 tickets)

Cascade+infra:
- T-050 Persistent audit_log tabel + GDPR-instrumentatie (cross-cutting, medium+)
- T-051 Simulator v1 synthetic contract flow (UI + orchestration)

Multi-tenant polish:
- T-052 Naming drift fix owning_account_id → basejump_account_id (chore, klein)
- T-053 Tenant-scoped parameter overrides (feature, groot want cascade-signature change)

Simulatie-uitbreiding:
- T-054 Scenario reproducibility param_snapshot_batch_id op dim_scenario
- T-055 Populatie-cascade write path (persist naar fact_loonkost)
- T-056 Subset-selectie uitbreiding (pc_id, status, gewest, ancienniteit)
- T-057 Unified scenario mutator (loon + wagen + extralegaal in één RPC)

## Aandachtspunten voor volgende sessie

1. **Populatie-snapshot consolidation-migration**: T-046 productie stap5 + T-047 stap6b + eventueel stap8/9 tenant-context. Iteration-5 op cascade_populatie_snapshot. Overweeg meteen te doen ipv de kleine incrementen.
2. **ISS-030 fix**: basejump-supabase_test_helpers extension in Docker container beschikbaar maken. Post-install script of Dockerfile aanpassing. Dev-productiviteit x N.
3. **T-053 impact**: als je multi-tenant echt gaat pakken, breekt de signature van elke cascade-functie. Overweeg of Laag 4b nog nodig heeft voor "productie" of dat T-053 in een aparte Laag 4c thuishoort.
4. **POC_UNVERIFIED tarieven**: T-047 eindejaarspremie coefficients, T-049 arbeidsongevallen tarieven, T-048 wagen indexatie — allemaal POC-schattingen die pre-productie cross-check nodig hebben. Structureel patroon: hoort in productie-checklist.
5. **Terminologie-drift (N-010)**: contract vs medewerker naming staat open. UI-only rename volstaat voor POC.

## Interessante ontdekkingen

- Effective-dating is DB-enforced (btree_gist), niet convention → sterk anker voor productie-migraties.
- Populatie-snapshot heeft nu 4 iteraties op één dag (T-039 → T-058 → ISS-076 → nog te doen T-046+T-047 integratie). DROP+CREATE FUNCTION churn is voelbaar. Volgende iteratie: batch alle uitbreidingen in één migration.
- Regex-based toepassing parsing in T-046 is expressief maar brittle. Volgende iteratie zou structured keys in formule_json willen.

## State

- Tickets: 50/58 complete
- Issues: 13 open (allemaal actionable)
- Lessons: 4 active
- Notes: 7 active (incl. N-010 terminologie-drift)
- Snapshot: fresh (net genomen)
- Handovers: 36 (deze)