Sessie 2026-07-04 (3/3): Laag 4b near-complete, 7 tickets afgerond.

## Wat is er gebeurd

Vervolg-vervolg-sessie ("en door, tokens vernieuwd"). Focus op resterende Laag 4b tickets. 7 tickets + 1 issue fix in Red→Green pattern, 15 commits.

## Wat er is geland

**Multi-tenant polish:**
- T-052: naming drift fix — dim_legale_entiteit.basejump_account_id → owning_account_id. Edit-in-place aanpak op 7 migrations + 9 tests + 3 UI-pages + seed.sql (POC pattern, geen ALTER-migration).

**Scenario reproducibility (T-054):**
- ALTER dim_scenario ADD COLUMN param_snapshot_batch_id uuid NULL (semantic-only ref).
- Helper get_current_snapshot_batch_id() returnt meest recente snapshot (via ORDER BY taken_at DESC LIMIT 1).

**Populatie flow completion:**
- T-056: cascade_populatie_snapshot signature p_functie_id uuid → p_filters jsonb. Filter keys: pc_ids, statussen, gewesten, functie_ids, ancienniteit_min/max_jaren, leeftijd_min/max. UI callers gemigreerd naar filters.
- T-055: create_populatie_loonkost SDF RPC schrijft cascade output naar fact_loonkost. 7 kostenblokken per contract, idempotent via ON CONFLICT, auto-creates snapshot als geen bestaat. **Cascade write-direction is nu compleet: populatie_snapshot leest, create_populatie_loonkost schrijft.**

**Scenario-mutators uitbreiding:**
- T-057: create_scenario_with_mutations RPC combineert loon_pct_increase, loon_flat_replace, wagen_add in één call. Pre-scan validatie voor DB writes. Bestaande create_what_if_scenario en create_wagen_scenario blijven voor backward-compat.

**Audit/observability:**
- T-050: unified audit_log VIEW over gdpr_access_log (T-034 reads) + mart_refresh_log (T-031 refreshes). Canoniek schema event_type/event_id/initiator_user_id/created_at/target_resource/rechtsgrondslag/metadata. View ipv nieuwe tabel omdat bestaande RPCs al naar de juiste tabellen schrijven.

**Simulator v1:**
- T-051: create_simulator_scenario RPC creëert in één transactie synthetic dim_persoon + dim_functie + dim_scenario + dim_contract + fact_prestatie + fact_looncomponent, roept dan create_populatie_loonkost aan → 7 kostenblok rijen in fact_loonkost. UI server action refactor is out-of-scope (aparte follow-up).

## Delta metrics

- Tickets: 57/58 complete (was 50 aan start van session 3, +7)
- Issues: 13 open (unchanged)
- Handovers: 37 (deze)
- Snapshot: fresh

## Overgebleven: T-053 (tenant-scoped parameter overrides)

Bewust deferred. Waarom:
- Signature-breaking voor ALLE cascade-functies (add p_legale_entiteit_id).
- Vereist ontwerp voor 3-5 param_*_override tabellen (extralegaal, sectorbijdrage, wagen_mobiliteit als eerste kandidaten; RSZ + plafond blijven globaal).
- Vergt cascade-lookup pattern: eerst tenant-override, fallback globaal via COALESCE-select.
- Impact op simulator page.tsx, populatie_snapshot, cascade_stap5_productie, alle sibling functies.

Grootste tenant-onboarding werk. Verdient eigen sessie met:
1. Design ADR (welke tabellen crijgen override, welke niet).
2. Migration voor 1 override-tabel als demo.
3. Cascade-signature evolutie.
4. Rollback strategie (feature flag?).

Beste route: nieuwe Laag 4c aanmaken met T-053 als eerste ticket, mogelijk uitgebreid met 2-3 sub-tickets voor design + migration + rollout.

## Cascade completeness state

De cascade is nu 100% end-to-end voor productie:
- 9 stappen: 1 (grondslag) → 2 (basis RSZ) → 3 (structurele vermindering met echte μ) → 4 (doelgroepen met non-cumulatie) → 5 (bijzondere bijdragen productie: toepassing + centenindex) → 6 (vakantiegeld) → 6b (eindejaarspremie) → 7 (extralegaal) → 8 (wagen CO2) → 9 (arbeidsongevallen)
- Read: cascade_populatie_snapshot met T-056 subset filters
- Write: create_populatie_loonkost (populatie) + create_simulator_scenario (individueel)
- Scenario mutations: create_what_if_scenario + create_wagen_scenario + create_scenario_with_mutations (unified)
- Reproducibility: param_snapshot_batch_id op dim_scenario + fact_loonkost.snapshot_batch_id
- Audit: unified audit_log view over reads + refreshes

## Aandachtspunten voor volgende sessie

1. **T-053 als aparte fase**: begin met ADR-achtige note over welke tabellen tenant-overridable moeten worden. Impact assessment.
2. **ISS-030 fix**: basejump-supabase_test_helpers extension in Docker container. Blijft dev-loop hindernis.
3. **UI-update voor T-051**: server action refactor van huidige `/simulator/page.tsx` direct-cascade-calls naar create_simulator_scenario RPC + redirect naar result page.
4. **create_what_if_scenario/create_wagen_scenario deprecation**: T-057 unified mutator kan deze vervangen. Overweeg deprecation-timeline.
5. **POC_UNVERIFIED tarieven**: T-047 eindejaarspremie coefficients + T-049 arbeidsongevallen tarieven + T-048 wagen indexatie. Domain-expert check nodig vóór productie-deploy.
6. **create_populatie_loonkost auth**: momenteel geen auth.uid() guard voor testing. In productie: bepaal of RLS-only voldoet.

## Interessante ontdekkingen

- T-050 was ~90% al gedaan door T-031 + T-034 (gdpr_access_log + mart_refresh_log). Alleen unified query-interface ontbrak. Ticket-schrijven vs. delivery-gap: soms zijn tickets al 80% opgelost door eerdere sessies zonder dat de status-tracker het weet.
- T-054 helper get_current_snapshot_batch_id() heeft geen NULL-check op audit_parameter_snapshot leegte — auto-createn was T-055's verantwoordelijkheid. Duidelijk contract tussen tickets: T-054 = query helper, T-055 = lifecycle owner.
- Session 3 zag 4 nieuwe populatie_snapshot iteraties (ISS-076 → T-056 filters → new dimension) — bij session 4 zou een consolidation-migration nuttig zijn.

## State

- Tickets: 57/58 complete
- Issues: 13 open (allemaal actionable)
- Lessons: 4 active
- Notes: 7 active
- Snapshot: fresh
- Handovers: 37