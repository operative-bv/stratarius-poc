# Implementation Plan: Rekencascade — van feit tot loonkost

**Branch**: `001-rekencascade` | **Date**: 2026-07-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-rekencascade/spec.md`

**First slice**: T-022 (fact tables migration) — start van een 8-ticket implementatie-sequentie binnen deze feature. Deze plan dekt de HELE cascade-architectuur; T-022 concrete implementatie-details staan in Phase 1 data-model.md en tasks.md (via `/speckit-tasks`).

## Summary

Rekencascade transformeert per (contract, periode, scenario) de rauwe input-feiten (loon-componenten, prestaties, wagen-data) via een 9-stappen deterministische cascade naar een uitgesplitste `fact_loonkost` breakdown per kostenblok. Alle bedragen komen uit de effective-dated parameterlaag (11 tabellen, 44 baseline-rijen); alle gedragslogica komt uit `dim_looncomponent`/`dim_prestatiecode` gedragstags. De cascade wordt geïmplementeerd als een reeks pure plpgsql functies, elk test-first per Principe V, verankerd tegen een audit-snapshot (T-021) voor reproduceerbaarheid.

Deze eerste ticket-slice (T-022) legt de output-tabel + de 3 input-fact-tabellen aan met een AFGELEID-invariant op `fact_loonkost` — geen handmatige writes toegestaan. Volgende slices (T-023 uurloon, T-024 μ, T-025 round_final, T-026-28 cascade-stappen, T-029 refscenarios) bouwen daarop verder.

## Technical Context

**Language/Version**: PostgreSQL 15 (plpgsql voor cascade-functies) + TypeScript 5 (Next.js 14, alleen voor toekomstige simulator UI in Phase 7 — niet relevant voor Phase 5 rekencascade)

**Primary Dependencies**: Supabase managed (Postgres 15 + PostgREST + Auth + basejump multi-tenant) — bestaand; geen nieuwe runtime dependencies voor rekencascade

**Storage**: PostgreSQL 15 via Supabase managed EU. Numeric-precisie `numeric(18,4)` voor tussentijdse berekeningen per Constitution v1.0.1.

**Testing**: pgTAP (bestaand: 40 assertion-suites in `supabase/tests/database/`). Blocked ISS-030: `basejump-supabase_test_helpers` extensie ontbreekt lokaal — verify blijft via `docker exec psql` handmatige smoke + hosted CI.

**Target Platform**: Supabase managed EU + Vercel EU (bestaande deploy-target; cascade zelf is puur database-side).

**Project Type**: web-service (Next.js + Supabase backend). Rekencascade is pure database-side feature; geen frontend-code in Phase 5.

**Performance Goals**: cascade voor 1 contract × 1 periode × 1 scenario voltooit in <500ms (POC). Determinisme heeft prioriteit over throughput. Geen bulk-optimalisaties in POC.

**Constraints**:
- **Deterministisch** (Constitution Principe III MUST regel 127): identieke input + snapshot ⇒ byte-identical output over onbeperkt aantal herhalingen.
- **Cent-precisie**: alle tussentijdse berekeningen `numeric(18,4)`. Afronding uitsluitend via `round_final()` (T-025) op eindpresentatie per kostenblok.
- **Geen bedragen in code**: 0 hardcoded numerieke tarieven/plafonds. Alles via temporele join op `param_*`.
- **AFGELEID-invariant**: `fact_loonkost` heeft trigger die handmatige INSERT/UPDATE weigert; enkel canonieke cascade-functie mag schrijven.
- **Test-first NON-NEGOTIABLE** (Principe V): elke pure functie heeft failende pgTAP test vóór implementatie-commit.

**Scale/Scope**: POC — 1-10 contracten × 1-3 scenarios voor demonstratie. Multi-tenant via bestaand basejump RLS-pattern (contract → legale_entiteit → basejump.account). Bulk-cascade (100+ contracten tegelijk) valt buiten POC-scope; kan later parallelized worden.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Constitution v1.0.1** definieert 5 non-negotiable principes. Elk gecheckt tegen deze feature:

### Principe I — Effective-Dating Everywhere ✅ PASS

- **MUST**: elke parameter draagt `geldig_van` + `geldig_tot`. → Al voldaan door T-015 t/m T-020; cascade doet uitsluitend temporele **read**-joins.
- **MUST**: forecasting ondersteund. → Cascade accepteert scenario met periode `geldig_van > current_date` via dezelfde temporele lookup.
- **MUST NOT**: geen UPDATE buiten typo-fix. → Rekencascade is read-only op parameterlaag.

**Cascade impact**: bij elke parameter-lookup joint de cascade op `WHERE contract.periode <@ daterange(param.geldig_van, coalesce(param.geldig_tot, 'infinity'::date), '[)')`. Geen andere lookup-strategie toegestaan.

### Principe II — Data-Driven Behavior, No Hardcoded Logic ✅ PASS

- **MUST**: nieuwe loonvorm = SQL insert in `dim_looncomponent` met correcte gedragstags. → Cascade leest tags; geen code-wijziging nodig voor nieuwe componenten.
- **MUST NOT**: geen `if component_code == 'XYZ'` in de cascade. → FR-009 codificeert dit.

**Cascade impact**: kostenblok-berekening groepeert `fact_looncomponent` rijen via `dim_looncomponent` gedragstags (bv. `rsz_plichtig = true` → optellen in RSZ-grondslag). Nooit via `component_id` of `familie` matching.

### Principe III — Strict Separation of Parameters, Facts, and Logic ✅ PASS

- **MUST**: één tariefwijziging = één rij in parameterlaag. → Cascade schrijft nooit naar `param_*`.
- **MUST**: cascade is deterministisch en bij-effectvrij. → Elke stap is pure functie; volledige input via functie-argumenten (`snapshot_batch_id`, `scenario_id`, `contract_id`, `periode`); output = rijen in `fact_loonkost`.
- **MUST NOT**: geen bedragen als constanten in code. → Cascade-functies bevatten alleen berekeningsformules; alle numerieke waarden komen uit temporele joins op `param_*`.

**Cascade impact**: `create_loonkost_cascade(contract_id, periode, scenario_id, snapshot_batch_id) returns fact_loonkost[]` — signatuur is inputs-only. Geen state, geen zij-effecten buiten fact_loonkost-inserts.

### Principe IV — Two Fractions, Never Conflated ✅ PASS

- **MUST**: elke berekening documenteert welke breuk gebruikt wordt en waarom. → Cascade-code én tests zullen expliciet per stap zeggen "uses fte_breuk" of "uses μ".
- **MUST NOT**: geen aggregatie/substitutie/coalesce van fte_breuk door μ of omgekeerd. → Twee aparte kolommen in cascade-context; twee aparte functies (`uurloon_van_maandloon` gebruikt fte_breuk; `mu_van_prestatie` levert μ; kostenblok-verminderingen consumeren μ).

**Cascade impact**: FR-006 codificeert dit. Test suite (T-029) bevat expliciete referentiescenario met `fte_breuk=1 ∧ μ<1` (tijdskrediet) om regressie te vangen.

### Principe V — Test-First for the Calculation Cascade (NON-NEGOTIABLE) ✅ PASS

- **MUST**: elke cascade-stap heeft unit test per werkgeverscategorie (1/2/3), per tariefwijziging-tijdvak, per grensgeval. → Reference-scenario suite T-029 wordt eerst geschreven; cascade-functies passen daarna.
- **MUST**: testcases citeren de bron. → pgTAP test-namen bevatten "RSZ 2024/1 sectie X" of "PC 200 CAO artikel Y".
- **MUST NOT**: geen implementatiecode zonder falende test eerst. → Task-volgorde in `/speckit-tasks` forceert test-vóór-code per pure functie.

**Cascade impact**: dit is de gate die de héle speckit-flow rechtvaardigt. Storybloq's plan-then-implement volgorde vervangt door test-first per pure functie. Elke ticket-slice krijgt pgTAP tests eerst (Red), dan implementatie tot Green.

### Gate resultaat

✅ **Alle 5 principes zonder violation**. Geen Complexity Tracking entries nodig. Feature is constitution-compliant by design.

## Project Structure

### Documentation (this feature)

```text
specs/001-rekencascade/
├── plan.md              # This file (/speckit-plan output)
├── spec.md              # Feature spec (from /speckit-specify)
├── research.md          # Phase 0 output — schema decisions, AFGELEID mechanism keuze
├── data-model.md        # Phase 1 output — fact table schemas, cascade-context entity
├── quickstart.md        # Phase 1 output — hoe cascade lokaal te testen
├── contracts/           # Phase 1 output — cascade function signatures + return types
│   ├── create_loonkost_cascade.md
│   ├── uurloon_van_maandloon.md
│   ├── mu_van_prestatie.md
│   └── round_final.md
├── checklists/
│   └── requirements.md  # Van /speckit-specify (al ingevuld)
└── tasks.md             # Phase 2 output (via /speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
supabase/
├── migrations/
│   ├── 20260703200000_fact_tables.sql             # T-022: fact_looncomponent + fact_prestatie + fact_wagen + fact_loonkost + AFGELEID-trigger
│   ├── 20260703210000_uurloon_function.sql        # T-023: uurloon_van_maandloon() pure functie
│   ├── 20260703220000_mu_function.sql             # T-024: mu_van_prestatie() pure functie
│   ├── 20260703230000_round_final_function.sql    # T-025: round_final() centrale afronding
│   ├── 20260703240000_cascade_step_1_to_3.sql     # T-026: bruto → RSZ-grondslag → basis patronale → structurele
│   ├── 20260703250000_cascade_step_4_to_6.sql     # T-027: doelgroep → bijzondere bijdragen → provisies
│   ├── 20260703260000_cascade_step_7_to_9.sql     # T-028: extralegaal → wagen → arbeidsongevallen
│   └── 20260703270000_cascade_orchestrator.sql    # create_loonkost_cascade() die 9 stappen aanroept
├── tests/database/
│   ├── 39-fact-tables.sql                         # T-022 pgTAP: schema shape + AFGELEID negative test
│   ├── 40-uurloon-function.sql                    # T-023 pgTAP tests EERST
│   ├── 41-mu-function.sql                         # T-024 pgTAP tests EERST
│   ├── 42-round-final-function.sql                # T-025 pgTAP tests EERST
│   ├── 43-cascade-step-1-to-3.sql                 # T-026 pgTAP + refscenario tests
│   ├── 44-cascade-step-4-to-6.sql                 # T-027 pgTAP + refscenario tests
│   ├── 45-cascade-step-7-to-9.sql                 # T-028 pgTAP + refscenario tests
│   ├── 46-cascade-orchestrator.sql                # E2E cascade tests
│   └── 47-referentiescenarios.sql                 # T-029 RSZ-brochure profielen (minimaal 5)
└── functions/                                     # (Optioneel later: edge functions voor cascade-trigger via API)
```

**Structure Decision**: pure database-side implementation. Alle cascade-functies zijn plpgsql, ge-versioneerd via `supabase/migrations/`. Tests via bestaande pgTAP infrastructure. Geen nieuwe backend/frontend directory nodig voor Phase 5 — de simulator UI komt in Phase 7 (Next.js in `src/app/`). Deze structuur volgt het gevestigde POC-pattern (T-012 t/m T-021) — geen infrastructuur-verandering, alleen nieuwe migration + test files per ticket.

**Migration nummering**: `20260703200000` + 010000 per ticket-slice, matcht chronologische deployment-volgorde en Supabase migration-runner conventies.

## Complexity Tracking

*Alle Constitution-gates gepassed zonder violation. Geen entries.*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| (geen)    | (geen)     | (geen)                               |

## Phase 0 — Research (unknowns to resolve)

Voor deze feature (met focus op T-022 als eerste slice) zijn de open vragen:

1. **AFGELEID-invariant mechanism**: hoe voorkom je handmatige INSERT/UPDATE op `fact_loonkost`?
   - Optie A: trigger die INSERT/UPDATE aborteert tenzij `current_setting('app.cascade_active')` = 'true'
   - Optie B: RLS policy die alleen `service_role` toestaat + SECURITY DEFINER function als schrijfroute
   - Optie C: geen `INSERT` grant aan enige rol; alleen SECURITY DEFINER function met eigen owner-permissions
   - **Beslissing verwacht in research.md**

2. **Scenario-scoping voor fact tables**: heeft elke fact table een `scenario_id`?
   - fact_prestatie / fact_wagen zijn conceptueel scenario-onafhankelijk (fysieke werkelijkheid)
   - fact_looncomponent kan scenario-gebonden zijn (bv. "wat-als bonus €500 hoger")
   - fact_loonkost is ALTIJD scenario-gebonden (output per scenario_id)
   - **Beslissing verwacht: fact_looncomponent en fact_loonkost dragen scenario_id; fact_prestatie en fact_wagen niet**

3. **Periode representation**: `date` (maand-begin), `daterange`, of `smallint jaar + smallint maand`?
   - PDF gebruikt maand-granulariteit voor RSZ (kwartalen voor plafonds)
   - Effective-dating pattern gebruikt daterange elders
   - **Beslissing verwacht: `periode date` (maand-begin: 2024-03-01) + CHECK `date_trunc('month', periode) = periode`**

4. **fact_loonkost.kostenblok CHECK enum-values**: exacte lijst?
   - Ticket description noemt: bruto, werkgevers_rsz, vakantiegeld, ejp, extralegaal, wagen_tco, arbeidsongevallen
   - **Beslissing: dit is de canonieke lijst; strict CHECK constraint**

5. **RSZ-brochure referentiescenarios**: welke 5 concrete profielen kiezen?
   - Bediende cat 1, arbeider cat 1, arbeider cat 3, contract met bedrijfswagen, contract met doelgroepvermindering
   - **Beslissing: neem PDF Laag 3 tabel-voorbeelden als startpunt**

**Output**: `research.md` met bovenstaande beslissingen + brondocument-verwijzingen.

## Phase 1 — Design & Contracts

### data-model.md — Fact table schemas

Voor T-022 concreet: 4 tabellen (fact_looncomponent, fact_prestatie, fact_wagen, fact_loonkost) + hun kolommen, FK's, RLS (via contract → legale_entiteit → basejump.account), CHECK constraints (kostenblok enum), en de AFGELEID-invariant.

Voor volgende slices: uitbreiding met cascade-context virtual entity, uurloon-context, μ-context.

### contracts/ — Cascade function signatures

Per pure functie een contract-file:

- `contracts/create_loonkost_cascade.md`: `create_loonkost_cascade(contract_id uuid, periode date, scenario_id uuid, snapshot_batch_id uuid) returns table (kostenblok text, bedrag numeric(18,4))`. Idempotent per (contract, periode, scenario).
- `contracts/uurloon_van_maandloon.md`: `uurloon_van_maandloon(maandloon numeric(18,4), pc_id text, periode date) returns numeric(18,4)`. Pure, geen side-effects.
- `contracts/mu_van_prestatie.md`: `mu_van_prestatie(contract_id uuid, periode date) returns numeric(6,4)`. Aggregeert `fact_prestatie` met `dim_prestatiecode.telt_voor_mu = true` filter.
- `contracts/round_final.md`: `round_final(bedrag numeric(18,4)) returns numeric(18,2)`. Banker's rounding.

### quickstart.md — Hoe cascade lokaal te testen

Stappen:
1. `supabase db reset` — apply alle migrations tot en met T-022 slice
2. Seed 1 test-contract via `insert into dim_persoon + dim_contract`
3. Seed fact_looncomponent + fact_prestatie voor Q1 2024
4. `select public.create_parameter_snapshot('cascade-test');` — gebruik T-021
5. `select * from public.create_loonkost_cascade(contract_id, '2024-01-01'::date, scenario_id, batch_id);`
6. Verify fact_loonkost breakdown matcht handmatige berekening

## Re-evaluatie Constitution Check post-Phase-1

Na data-model.md + contracts/ zullen we opnieuw langs de 5 principes lopen:
- Principe I: check dat elke cascade-parameter-lookup daterange gebruikt
- Principe II: check dat kostenblok-groupby op gedragstags gebeurt, niet component_id
- Principe III: check dat function signatures pure zijn (geen shared state, alleen args → return)
- Principe IV: check dat uurloon-contract en mu-contract expliciet verschillende breuk-argumenten hebben
- Principe V: check dat elke contract-file "test bestand X moet eerst falen" documenteert

Als post-design een violation blijkt, wordt Complexity Tracking ingevuld met justificatie.
