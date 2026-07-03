# Phase 1 Data Model: Rekencascade fact tables & cascade-context

**Date**: 2026-07-03
**Feature**: [spec.md](./spec.md) | Research decisions: [research.md](./research.md)

Dit document dekt de 4 fact tabellen (T-022 slice) + de virtueel/logische cascade-context die de tickets T-023 t/m T-028 nodig hebben. Elke tabel is specified als: fields, relationships, validation rules (uit FR's), state transitions.

---

## Entiteit: `fact_looncomponent`

**Beschrijving**: één rij per (contract, periode, component, scenario). Bevat het bedrag van een specifieke loonvorm (basisloon, premie, extralegaal cheque). Input voor de cascade.

**Kolommen**:

| Kolom | Type | NULL | Rationale |
|---|---|---|---|
| fact_looncomponent_id | uuid PK default gen_random_uuid() | not null | Surrogate PK |
| contract_id | uuid FK → dim_contract | not null | Multi-tenant scope via legale_entiteit ⇒ basejump.account |
| periode | date | not null | Maand-begin per Decision 3; CHECK `date_trunc('month', periode) = periode` |
| component_id | text FK → dim_looncomponent | not null | Data-driven gedrag via gedragstags |
| scenario_id | uuid FK → dim_scenario | not null | Per Decision 2 — scenario-varianten toegestaan |
| bedrag | numeric(18,4) | not null | Cent-precisie per Constitution v1.0.1; > 0 CHECK NIET afgedwongen (retro-correcties kunnen negatief zijn) |
| bron_ref | text | null | Optionele reference naar bron-document (bv. loonbrief-ID) |
| created_at, updated_at | timestamptz | not null | basejump.trigger_set_timestamps |

**Constraints**:
- Effective-dating: geen `geldig_van`/`geldig_tot` (fact tables zijn geen params; periode is de effective-dating dimensie).
- Exclusion: geen — meerdere componenten per (contract, periode) mogen bestaan (dat is de bedoeling).
- Unieke sleutel: `unique (contract_id, periode, component_id, scenario_id)` — één bedrag per (contract, periode, component, scenario).

**RLS**: contract-tenant scoping via `EXISTS (SELECT 1 FROM dim_contract c JOIN dim_legale_entiteit e USING (legale_entiteit_id) WHERE basejump.has_role_on_account(e.basejump_account_id))`.

**Validation regels** (uit FR's):
- FR-009: cascade groepeert deze rijen via `dim_looncomponent` gedragstags (`rsz_plichtig`, `is_werkgeverskost`, etc.) — niet via component_id.
- FR-010: `bedrijfswagen_vaa` rijen (waarbij `dim_looncomponent.is_werkgeverskost = false`) tellen niet mee in werkgeverskost-totaal.

---

## Entiteit: `fact_prestatie`

**Beschrijving**: één rij per (contract, periode, prestatiecode). Bevat uren + dagen per prestatiecode-type. Input voor μ = Q/S en overloon-detectie.

**Kolommen**:

| Kolom | Type | NULL | Rationale |
|---|---|---|---|
| fact_prestatie_id | uuid PK default gen_random_uuid() | not null | Surrogate PK |
| contract_id | uuid FK → dim_contract | not null | Tenant scope |
| periode | date | not null | Maand-begin; zelfde CHECK |
| prestatiecode_id | text FK → dim_prestatiecode | not null | Data-driven via gedragstags |
| uren | numeric(6,4) | not null | Breuk-precisie per Constitution; positief |
| dagen | numeric(6,4) | not null | Breuk-precisie |
| bron_ref | text | null | Loonbrief-ID etc. |
| created_at, updated_at | timestamptz | not null | Basejump trigger |

**Constraints**:
- CHECK `uren >= 0 AND dagen >= 0` — sanity, geen negatieve prestaties.
- Unieke sleutel: `unique (contract_id, periode, prestatiecode_id)`. Geen scenario_id (Decision 2: prestaties zijn fysieke werkelijkheid).

**RLS**: idem `fact_looncomponent` via `dim_contract`.

**Validation regels**:
- FR-012: μ = Q/S berekening filtert deze rijen op `dim_prestatiecode.telt_voor_mu = true`. Tijdelijke urenvermindering (`telt_voor_mu = false`) telt niet in Q.
- Overloon-detectie via `dim_prestatiecode.toeslag_pct > 0` — cascade telt overuren apart in RSZ-grondslag.

---

## Entiteit: `fact_wagen`

**Beschrijving**: één rij per (contract, periode). Bevat wagen-attributen voor VAA + CO2-solidariteitsbijdrage berekening.

**Kolommen**:

| Kolom | Type | NULL | Rationale |
|---|---|---|---|
| fact_wagen_id | uuid PK default gen_random_uuid() | not null | Surrogate PK |
| contract_id | uuid FK → dim_contract | not null | Tenant scope |
| periode | date | not null | Maand-begin |
| catalogus_waarde | numeric(18,4) | not null | Geldbedrag; > 0 CHECK |
| co2_g_km | smallint | not null | Discrete integer (idem `param_wagen_mobiliteit.referentie_co2`); CHECK BETWEEN 0 AND 500 |
| brandstoftype | text | not null | CHECK `IN ('benzine','diesel','elektrisch','hybride_benzine','hybride_diesel','lpg','cng','waterstof')` |
| aanschaffingsdatum | date | not null | Voor VAA-degressie-berekening |
| bron_ref | text | null | Wagen-registratie referentie |
| created_at, updated_at | timestamptz | not null | Basejump trigger |

**Constraints**:
- Unieke sleutel: `unique (contract_id, periode)`. Geen scenario_id (Decision 2).
- CHECK `catalogus_waarde > 0` en `co2_g_km BETWEEN 0 AND 500` en `aanschaffingsdatum <= periode`.

**RLS**: idem via `dim_contract`.

**Validation regels**:
- Cascade parseert `param_wagen_mobiliteit.co2_formule_json` en past de formule toe met deze fact_wagen-inputs.
- VAA-berekening gebruikt catalogus_waarde × brandstof-multiplier × leeftijd-degressie.

---

## Entiteit: `fact_loonkost` (OUTPUT-tabel)

**Beschrijving**: **AFGELEID** output-tabel. Één rij per (contract, periode, kostenblok, scenario). Bevat het afgeronde bedrag per kostenblok, geproduceerd door de cascade.

**Kolommen**:

| Kolom | Type | NULL | Rationale |
|---|---|---|---|
| fact_loonkost_id | uuid PK default gen_random_uuid() | not null | Surrogate PK |
| contract_id | uuid FK → dim_contract | not null | Tenant scope |
| periode | date | not null | Maand-begin CHECK |
| kostenblok | text | not null | CHECK `IN ('bruto','werkgevers_rsz','vakantiegeld','ejp','extralegaal','wagen_tco','arbeidsongevallen')` per Decision 4 |
| scenario_id | uuid FK → dim_scenario | not null | Per Decision 2 — output altijd scenario-gebonden |
| bedrag | numeric(18,4) | not null | Cent-precisie; opgeslagen als afgeronde numeric(18,4) na `round_final()` toepassing |
| snapshot_batch_id | uuid FK → audit_parameter_snapshot(snapshot_batch_id) | not null | Reproducibility link naar T-021 audit — welke parameter-snapshot geproduceerde dit bedrag |
| cascade_run_at | timestamptz | not null default now() | Tijdstip van cascade-run |
| created_at, updated_at | timestamptz | not null | Basejump trigger |

**Constraints**:
- Unieke sleutel: `unique (contract_id, periode, kostenblok, scenario_id)`.
- CHECK `date_trunc('month', periode) = periode`.
- **AFGELEID-invariant**: `REVOKE INSERT, UPDATE, DELETE FROM authenticated, public, anon`. Enige schrijfroute is `create_loonkost_cascade()` SECURITY DEFINER function (Decision 1).

**RLS**: idem via `dim_contract`. Read-only voor authenticated.

**Validation regels** (uit FR's):
- FR-001: 7 kostenblokken (canonical set).
- FR-003: geen handmatige INSERT/UPDATE toegestaan.
- FR-004: reproduceerbaarheid via `snapshot_batch_id`.
- FR-013: meerdere scenarios per (contract, periode) mogen naast elkaar bestaan.

**State transitions**:
- INSERT: alleen via `create_loonkost_cascade()`. Bij re-run met identieke inputs: verwacht overwrite (ON CONFLICT (contract, periode, kostenblok, scenario) DO UPDATE) OF eerst DELETE, dan INSERT. Beslissing: **ON CONFLICT DO UPDATE** — houdt de row-id stabiel, alleen bedrag + cascade_run_at + snapshot_batch_id worden bijgewerkt.
- UPDATE: alleen via zelfde function.
- DELETE: niet toegestaan (append-only log-semantiek).

---

## Virtueel entity: Cascade-context

**Beschrijving**: geen fysieke tabel; bundelt de 4 inputs die elke cascade-run nodig heeft. Geïmplementeerd als functie-argumenten.

**Fields**:

| Field | Type | Bron |
|---|---|---|
| contract_id | uuid | Argument bij invocation |
| periode | date | Argument (maand-begin) |
| scenario_id | uuid | Argument — verwijst naar `dim_scenario` |
| snapshot_batch_id | uuid | Argument — verwijst naar `audit_parameter_snapshot(snapshot_batch_id)` uit T-021 |

**Validation** (bij function-entry):
- `contract_id` moet bestaan in `dim_contract` waar `basejump.has_role_on_account(...)` matcht.
- `periode` moet `date_trunc('month', periode) = periode` voldoen.
- `scenario_id` moet bestaan én verwijzen naar contract's `legale_entiteit_id`.
- `snapshot_batch_id` moet bestaan in `audit_parameter_snapshot`.
- Bij missing: EXPLICIET falen met specifieke fout (FR-016).

---

## Cascade dataflow

```
Input:
  fact_looncomponent [contract, periode, scenario]
  fact_prestatie     [contract, periode]
  fact_wagen         [contract, periode]
  (param_* via temporele join op periode; welke snapshot: via snapshot_batch_id)

Cascade (9 stappen T-026 t/m T-028):
  1. bruto → RSZ-grondslag         ← uses fact_looncomponent (rsz_plichtig=true), fact_prestatie (toeslag_pct voor overloon)
  2. basis patronale RSZ           ← uses param_rsz (via contract.werkgeverscategorie, periode)
  3. structurele vermindering      ← uses param_structurele_vermindering, μ (van T-024)
  4. doelgroepverminderingen       ← uses param_doelgroepvermindering (via contract.legale_entiteit.gewest, periode), μ
  5. bijzondere bijdragen          ← uses param_bijzondere_bijdragen (per type)
  6. provisies (vakantiegeld+EJP) ← uses param_vakantiegeld, param_extralegaal
  7. extralegale voordelen        ← uses param_extralegaal, fact_looncomponent (extralegaal familie)
  8. wagen & mobiliteit           ← uses param_wagen_mobiliteit, fact_wagen (VAA-scheiding!)
  9. arbeidsongevallen            ← uses fixed tarief (out-of-scope voor eerste MVP; placeholder ~1%)

Output:
  fact_loonkost [contract, periode, kostenblok, scenario, bedrag, snapshot_batch_id]
    – één rij per canonieke kostenblok (bruto, werkgevers_rsz, ..., arbeidsongevallen)
```

Elke cascade-stap zoekt zijn parameters via temporele join `WHERE periode >= param.geldig_van AND (param.geldig_tot IS NULL OR periode < param.geldig_tot)`. Geen alternatieve lookup-strategie.

---

## T-022 scope

T-022 implementeert **alleen** de 4 tabellen + AFGELEID-invariant + RLS. De cascade-functies (T-023 t/m T-028) komen in latere migrations.

**pgTAP tests voor T-022**:
1. Schema shape: 4 has_table, 4 col_is_pk, col_type_is voor `bedrag numeric(18,4)`
2. NOT NULL smoke op alle NOT NULL kolommen (min 15 total)
3. CHECK constraints: `periode = date_trunc('month', periode)`, kostenblok enum, brandstoftype enum
4. Unique keys per tabel (fact_looncomponent, fact_prestatie, fact_wagen, fact_loonkost)
5. RLS: contract-scoped read voor tenant; anon block
6. **AFGELEID-invariant negative test**: authenticated INSERT op fact_loonkost → throws_ok 42501
7. **AFGELEID-invariant positive test**: service_role INSERT (of via placeholder function) → lives_ok
8. FK integrity: invalid contract_id / scenario_id / snapshot_batch_id → 23503

Geschat plan(N): ~22-25 assertions.
