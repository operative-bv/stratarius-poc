# Phase 0 Research: Rekencascade (focus T-022 fact tables slice)

**Date**: 2026-07-03
**Feature**: [spec.md](./spec.md) | [plan.md](./plan.md)

Deze research resolvet de 5 NEEDS CLARIFICATION items uit plan.md Phase 0 sectie. Elke beslissing bevat rationale + verworpen alternatieven.

---

## Decision 1: AFGELEID-invariant mechanism voor `fact_loonkost`

**Beslissing**: **Optie C — geen INSERT/UPDATE/DELETE grant aan authenticated of anon; SECURITY DEFINER function als enige schrijfroute**.

Concreet:
- Op `fact_loonkost`: `REVOKE INSERT, UPDATE, DELETE FROM authenticated, public, anon`.
- `create_loonkost_cascade(...)` function is `SECURITY DEFINER` met pinned search_path (idem T-021 pattern) en heeft `GRANT EXECUTE TO service_role`.
- De function is de canonieke schrijfroute; niets anders mag INSERTs doen.
- Postgres owner (`postgres`) blijft impliciet INSERT-toegang hebben voor migrations/seed.

**Rationale**:
- Volgt exact T-021 audit-snapshot pattern dat al in review-cyclus succesvol was.
- Minimaal aantal moving parts (geen trigger, geen custom flag).
- Trigger-based mechanism (Optie A) heeft een subtiele failure mode: als de cascade-function een INSERT doet zonder eerst `SET LOCAL app.cascade_active = 'true'`, faalt de trigger; makkelijk te vergeten bij nieuwe cascade-stappen.
- RLS-based mechanism (Optie B) mengt de schrijf-invariant met tenant-scoping — twee concerns door elkaar.
- Optie C houdt de invariant in de GRANT/REVOKE layer waar het semantisch thuis hoort.

**Verworpen alternatieven**:
- **Optie A (trigger + session flag)**: fragile — vereist dat cascade-code overal `SET LOCAL` doet vóór INSERT. Bij programmeerfout: silent write-through in ontwikkeling, potentially catastrofisch in productie.
- **Optie B (RLS + service_role only)**: RLS is primair voor tenant-scoping (contract → legale_entiteit → basejump.account); overloaden met "AFGELEID"-semantiek maakt policy-audit ingewikkelder.

**Test-vereiste**: pgTAP negative test die `set local role authenticated` doet en `throws_ok 42501` bij directe INSERT verwacht. Positieve test roept `create_loonkost_cascade()` aan als service_role en verifieert dat het slaagt.

---

## Decision 2: `scenario_id` scoping per fact table

**Beslissing**: **fact_looncomponent en fact_loonkost dragen `scenario_id NOT NULL`; fact_prestatie en fact_wagen NIET (scenario-onafhankelijk)**.

Concreet:
| Tabel | scenario_id | Rationale |
|---|---|---|
| `fact_looncomponent` | ✅ NOT NULL FK → dim_scenario | Loon-componenten kunnen scenario-specifiek zijn (bv. what-if "bonus €500 hoger"). |
| `fact_prestatie` | ❌ | Prestaties zijn fysieke werkelijkheid (uren + dagen); een what-if-scenario "als je 40u ipv 38u werkt" zou een nieuw contract vereisen, niet een scenario-variant. |
| `fact_wagen` | ❌ | Wagen-attributen (catalogus_waarde, CO2, brandstoftype) zijn fysieke werkelijkheid van het voertuig; scenario-varianten via wagen-swap = nieuw contract. |
| `fact_loonkost` | ✅ NOT NULL FK → dim_scenario | Output ALTIJD scenario-gebonden — dat is de reden dat scenario's bestaan. |

**Rationale**:
- Constitution Principe III eist strikte scheiding facts vs parameters vs logica. Facts die de fysieke werkelijkheid representeren (prestaties, wagen) mogen niet scenario-varianten hebben zonder dat er iets wijzigt in de contract-realiteit.
- Loon-componenten kunnen redelijkerwijs varieren tussen scenario's (bonus-simulatie, extralegaal-varianten) zonder dat het contract zelf verandert.
- fact_loonkost is per definitie output per scenario.
- Cascade-context bevat expliciet `scenario_id` als input; dit forceert de programmeur om per cascade-run bewust een scenario te kiezen.

**Verworpen alternatieven**:
- **Alle 4 fact tables scenario-gebonden**: overcompliceert fact_prestatie en fact_wagen; leidt tot duplicate-data (dezelfde uren voor scenario A én scenario B).
- **Geen enkele fact table scenario-gebonden, alleen fact_loonkost**: verliest de mogelijkheid om what-if-loon-scenarios te simuleren zonder alle contract-data te dupliceren.

**Impact**: cascade-context is `(contract_id, periode, scenario_id, snapshot_batch_id)`. Bij het lezen van fact_prestatie/fact_wagen wordt scenario_id genegeerd (geen filter). Bij fact_looncomponent wordt scenario_id in de WHERE-clause gebruikt.

---

## Decision 3: Periode-representation

**Beslissing**: **`periode date NOT NULL CHECK (date_trunc('month', periode) = periode)` — een `date` kolom die altijd de eerste van de maand is**.

Concreet:
- Kolom-type: `date`
- Semantiek: de eerste dag van de maand (2024-03-01 = maart 2024)
- CHECK constraint: `date_trunc('month', periode) = periode` weigert non-maand-begin datums
- Cascade-berekeningen gebruiken `periode` voor temporele join tegen `param_*` tabellen: `WHERE periode >= param.geldig_van AND (param.geldig_tot IS NULL OR periode < param.geldig_tot)`

**Rationale**:
- PDF gebruikt maand-granulariteit voor RSZ + vakantiegeld; kwartaal-granulariteit voor plafonds. Kwartaal kan afgeleid worden uit maand-begin (`date_trunc('quarter', periode)`); reverse niet zonder informatieverlies.
- `date` is trivially indexeerbaar met btree; `daterange` vereist gist-index en is overkill voor punt-lookup.
- Consistent met bestaande `geldig_van`/`geldig_tot` in parameterlaag (beide `date`).
- CHECK constraint sluit fouten door programmeurs die per-week of per-dag periode-data willen inserteren.

**Verworpen alternatieven**:
- **`daterange`**: overkill voor puntobservatie. Cascade rekent per maand, niet per interval.
- **`smallint jaar + smallint maand`**: verliest datum-arithmetiek voor temporele join; PostgreSQL doet natuurlijk werk met `date`.
- **`text` (bv. "2024-03")**: geen type-safety, slechtere index, slechte temporele arithmetiek.

**Impact**: alle 4 fact tables gebruiken dezelfde `periode date` kolom-conventie. Cascade-orchestrator neemt periode als parameter en throws als het geen maand-begin is.

---

## Decision 4: `fact_loonkost.kostenblok` CHECK enum

**Beslissing**: **strikt CHECK constraint op canonieke lijst uit ticket-description**:

```sql
kostenblok text NOT NULL CHECK (kostenblok IN (
    'bruto',
    'werkgevers_rsz',
    'vakantiegeld',
    'ejp',
    'extralegaal',
    'wagen_tco',
    'arbeidsongevallen'
))
```

**Rationale**:
- 7 canonieke kostenblokken uit T-022 ticket-description = complete lijst voor Belgische werkgeverskost-uitsplitsing.
- Gesloten enum (idem `param_rsz.status`, `param_bijzondere_bijdragen.type`): schema-migratie nodig voor uitbreiding. Dit is bewust — nieuwe kostenblok = domein-wijziging die review verdient.
- Cascade-code gebruikt exact deze strings (constants); geen magic strings elders.

**Verworpen alternatieven**:
- **Free-form text (idem param_extralegaal.voordeeltype)**: kostenblokken zijn een gesloten domein per Belgische payroll-conventie. Open toestaan zou toevoegen aan gedoms van "wat betekent 'overige_kosten' precies?" over jaren.
- **Aparte `dim_kostenblok` FK**: overkill; 7 stabiele waarden, geen relationele attributen nodig.

**Test-vereiste**: pgTAP negative test met `throws_ok 23514` voor een non-canonieke kostenblok string zoals `'random'`.

---

## Decision 5: Referentiescenario-selectie (voor T-029 later)

**Beslissing**: **5 referentiescenarios uit PDF Laag 3 voorbeelden + RSZ 2024/1 gidsvoorbeelden**:

| # | Profiel | Kostenblokken getest | Verwacht kritiek |
|---|---|---|---|
| 1 | Bediende cat 1, PC 200, brutoloon €4.000/maand, geen extras | bruto, werkgevers_rsz, vakantiegeld, ejp | Basisberekening; sanity check |
| 2 | Arbeider cat 1, PC 111, brutoloon €3.500/maand, geen extras | Alle 4 + 108% factor toegepast | Verify basisfactor 108% + vakantiekas-behandeling |
| 3 | Arbeider cat 3 (beschutte werkplaats), PC 302, brutoloon €2.500 | Alle 4 + gunstregime cap | Verify laagste tarief 17.07% + cap 'gunstregime' |
| 4 | Bediende cat 1 met bedrijfswagen (benzine, CO2 100 g/km, catalogus €30k) | Alle 4 + wagen_tco + VAA-scheiding | Verify VAA-valkuil (VAA telt niet als werkgeverskost) |
| 5 | Bediende cat 1 met Vlaamse doelgroepvermindering "oudere_werknemer" (leeftijd 62) | Alle 4 + doelgroep-vermindering pro-rata μ | Verify μ vs fte_breuk scheiding + doelgroep-korting |

**Rationale**:
- Dekken de 4 unieke edge cases die spec.md identificeert: 108% factor, cat 3 gunstregime, VAA-valkuil, μ vs fte_breuk.
- 5 profielen is minimum uit spec SC-001 requirement.
- Elk profiel is een separate pgTAP suite met bron-verwijzing in test-namen ("RSZ 2024/1 sectie X").
- Verwachte bedragen komen uit handmatige berekening tegen de POC parameter-data (T-018/T-019/T-020 imports), niet uit RSZ-brochure tabellen (die 2024 exact bedragen bevatten die kunnen afwijken van onze POC placeholder-waarden).

**Verworpen alternatieven**:
- **RSZ-brochure exacte tabel-voorbeelden**: onze POC parameter-data is `[POC_UNVERIFIED_2024]` — brochure bedragen matchen niet exact. Beter: eigen handmatige berekeningen tegen onze imports; brochure-verwijzing als bron voor methodologie, niet voor exact-bedrag-match.
- **>5 profielen**: SC-001 eist minimaal 5; meer is nice-to-have voor T-029 uitbreiding, niet blocking voor eerste MVP.

**Test-vereiste**: elk profiel als aparte pgTAP suite met bron-verwijzing in test-namen. Tolerantie €0.01 per kostenblok. Delta t.o.v. verwacht bedrag wordt gerapporteerd in test-output.

---

## Samenvatting

Alle 5 NEEDS CLARIFICATION items uit Phase 0 sectie van plan.md zijn opgelost. Beslissingen sluiten aan bij bestaande project-patronen (T-021 SECURITY DEFINER, T-015 REVOKE + policy, T-017 CHECK enum, T-018 date-precision) en Constitution v1.0.1 principes.

**Ready voor Phase 1** (data-model.md, contracts/, quickstart.md).
