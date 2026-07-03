# Feature Specification: Rekencascade — van feit tot loonkost

**Feature Branch**: `001-rekencascade`

**Created**: 2026-07-03

**Status**: Draft

**Input**: User description: "rekencascade" (feature-level spec dekt Phase 5 tickets T-022 t/m T-029)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single-contract loonkost berekening (Priority: P1)

Een HR-partner of business analyst voert loonkost-input in voor één contract in één specifiek scenario (bv. actual 2024 of what-if "indexcoefficient +2%") en krijgt een deterministische, uitgesplitste totale werkgeverskost terug, samengesteld uit alle relevante kostenblokken (bruto, werkgevers-RSZ, vakantiegeld, eindejaarspremie, extralegaal, wagen-TCO, arbeidsongevallen). De cijfers matchen — binnen cent-tolerantie — een handmatige berekening met de RSZ-brochure als referentie.

**Why this priority**: Kernpropositie van de simulator. Zonder deze cascade werkt de POC niet. Alle andere features (multi-contract vergelijking, mart-analyses, wat-als scenarios) zijn afhankelijk van deze basiscapaciteit.

**Independent Test**: Kan volledig getest worden door één contract-input te leveren (fixed maandloon, werkgeverscategorie, PC, statuut, extralegaal-pakket), de cascade te draaien voor een scenario, en de output-breakdown te vergelijken met een bekend RSZ-brochure voorbeeld. Levert een correcte loonkost-uitsplitsing.

**Acceptance Scenarios**:

1. **Given** een bediende in werkgeverscategorie 1, PC 200, brutoloon €4.000, geen extralegale voordelen, geen bedrijfswagen, **When** de cascade wordt uitgevoerd voor scenario "actual 2024", **Then** produceert de cascade een `fact_loonkost` breakdown met kostenblokken bruto, werkgevers_rsz, vakantiegeld, ejp, met numerieke waarden die binnen €0.01 matchen met een handmatig-gecontroleerd voorbeeld.
2. **Given** een arbeider in werkgeverscategorie 1 met basisfactor 108%, **When** de RSZ-berekening plaatsvindt, **Then** wordt de grondslag vermenigvuldigd met 1.08 vóór het RSZ-tarief wordt toegepast.
3. **Given** een contract met tijdelijke urenvermindering (fte_breuk=1.0 maar effectieve μ=0.8), **When** de pro-rata verminderingen worden toegepast, **Then** worden ze geschaald met μ (niet met fte_breuk), en het verschil is expliciet zichtbaar in de output.
4. **Given** twee cascade-runs met identieke input + identieke `snapshot_batch_id`, **When** beide runs voltooien, **Then** produceren ze identieke output tot op de cent.

---

### User Story 2 - What-if scenario vergelijking (Priority: P2)

Dezelfde HR-partner wil naast het `actual` scenario ook een `what_if` scenario draaien (bv. "indexcoefficient +2%" of "nieuwe doelgroepvermindering vanaf juli"). Het systeem berekent beide scenarios voor hetzelfde contract, laat de delta zien per kostenblok, en behoudt beide runs traceerbaar via distinct `scenario_id`.

**Why this priority**: Simulaties zijn een uitbreiding van de basis, niet de kernkorrekthetheidsvereiste. Nodig voor de simulator UI (Phase 6) maar niet blocking voor het proof-of-concept dat de cascade correct rekent.

**Independent Test**: Draai P1 met scenario A, draai daarna met scenario B (dezelfde input, andere parameter-jaargang of andere doelgroep-status), toon delta breakdown. Levert twee vergelijkbare snapshots waarbij de verschillen alleen komen van de parameter-verschillen.

**Acceptance Scenarios**:

1. **Given** hetzelfde contract in scenario A (actual 2024) en scenario B (what_if index +2%), **When** de cascade in beide scenarios draait, **Then** verschillen alleen de kostenblokken die door de index-verandering geraakt worden (bruto, RSZ-grondslag, verminderingen), en de delta is arithmetisch verklaarbaar uit de parameter-delta.

---

### User Story 3 - Reproduceerbaarheid via audit (Priority: P3)

Een auditor of ontwikkelaar wil een historische cascade-uitkomst reproduceren voor een dispuut of regressie-test. Ze halen de originele `snapshot_batch_id` uit de audit-log op en draaien de cascade opnieuw met dezelfde fact-data — output moet identiek zijn.

**Why this priority**: Compliance / audit vereiste per Constitution Principe III MUST (regel 127). Belangrijk voor productie-vertrouwen maar niet blocking voor de MVP-simulator. Fundament al gelegd door T-021 audit-snapshot.

**Independent Test**: Neem een cascade-run uit een oude batch, herstel de fact-data (immutable), gebruik de originele `snapshot_batch_id` als input voor de cascade, verify byte-identical output. Levert reproduceerbaarheid-bewijs.

**Acceptance Scenarios**:

1. **Given** een historische cascade-run met `snapshot_batch_id X` en fact-data F, **When** de cascade opnieuw wordt uitgevoerd met dezelfde X + F na parameter-updates in de tussentijd, **Then** produceert de nieuwe run identieke `fact_loonkost` output (Constitution Principe III MUST — deterministisch).

---

### Edge Cases

- **Bedrijfswagen VAA-valkuil**: contract met bedrijfswagen krijgt zowel een `bedrijfswagen_vaa` component (fiscaal voordeel voor werknemer, `is_werkgeverskost=false`) als een `bedrijfswagen_tco` component (echte kost, `is_werkgeverskost=true`). Cascade moet deze scheiding respecteren — VAA telt niet als werkgeverskost.
- **Grens werkgeverscategorie**: contract dat over de kalenderjaargrens loopt terwijl parameters wijzigen (jaarwisseling 2024→2025). Cascade selecteert de correcte param-rij per periode via temporele join `geldig_van/geldig_tot`.
- **Multi-scenario cascade race**: twee scenarios (bv. actual + what_if) draaien voor hetzelfde contract op dezelfde periode; scenario_id disambiguateert de output-rijen zodat er geen exclusion-conflict is.
- **Ontbrekende parameter voor periode**: contract-periode valt buiten alle bestaande param-rijen (bv. 2026 zonder import). Cascade moet expliciet falen met een duidelijke fout (welke tabel, welke periode) i.p.v. NULL propaganderen.
- **CAO 90 bonusplan boven jaarplafond**: bonus die het CAO 90 jaarplafond overschrijdt. Cascade moet het overschot correct als normaal loon behandelen (niet als extralegaal).
- **Doelgroepvermindering die tijdens contract-periode afloopt**: doelgroepvermindering waarvan `geldig_tot` binnen de contract-periode valt. Cascade moet correct pro-rata schalen op de dagen vóór afloop.
- **Component met `telt_voor_mu=false` maar `telt_voor_vakantiegeld=true`**: gedragstags moeten onafhankelijk gerespecteerd worden — geen impliciete koppeling.
- **Arbeider werkgeverscategorie 3 (beschutte werkplaats)**: laagste basisbijdrage + 108% factor + gunstregime cap. Cascade combineert deze correct zonder dubbeltelling van de gunstregime-plafond.

## Requirements *(mandatory)*

### Functional Requirements

**Cascade-kernproces**

- **FR-001**: Systeem MOET voor elke combinatie van (contract, periode, scenario) een deterministische breakdown van totale werkgeverskost produceren in `fact_loonkost`, uitgesplitst per kostenblok uit de canonieke lijst: `bruto`, `werkgevers_rsz`, `vakantiegeld`, `ejp` (eindejaarspremie), `extralegaal`, `wagen_tco`, `arbeidsongevallen`.
- **FR-002**: De cascade MOET bestaan uit exact 9 stappen die in volgorde worden uitgevoerd: (1) bruto + overloon → RSZ-grondslag, (2) basis patronale RSZ berekening, (3) structurele vermindering, (4) doelgroepverminderingen, (5) bijzondere bijdragen, (6) provisies (vakantiegeld + EJP), (7) extralegaal, (8) wagen & mobiliteit, (9) arbeidsongevallen.
- **FR-003**: `fact_loonkost` MOET AFGELEID zijn — nooit handmatig ingevoerd. Een trigger of CHECK-constraint MOET direct handmatige INSERT/UPDATE weigeren behalve via de canonieke cascade-uitvoering.
- **FR-004**: Cascade-output voor een gegeven (contract, periode, scenario) input MOET reproduceerbaar zijn zolang de bijbehorende `snapshot_batch_id` uit T-021 herbruikbaar is (Constitution regel 127 MUST).

**Deterministische parameter-lookup**

- **FR-005**: De cascade MOET voor elke parameter-waarde een temporele join uitvoeren op basis van de contract-periode en de effective-dated `geldig_van`/`geldig_tot` van elke param_* tabel. Als voor een gegeven periode geen actieve parameter-rij bestaat, MOET de cascade falen met een expliciete fout (welke tabel, welke discriminator, welke periode).
- **FR-006**: De cascade MOET onderscheid maken tussen `fte_breuk` (statisch contract-attribuut) en `μ = Q/S` (dynamisch, afgeleid uit fact_prestatie/param_arbeidsduur). Pro-rata verminderingen (bv. structurele + doelgroep) MOETEN geschaald worden met μ, niet met fte_breuk (Principe IV).

**Afronding**

- **FR-007**: Systeem MOET alle tussentijdse berekeningen op `numeric(18,4)` cent-precisie uitvoeren; afronding MOET uitsluitend gebeuren door de centrale `round_final()` functie bij de eindpresentatie van elk kostenblok.
- **FR-008**: `round_final()` MOET banker's-rounding (round half to even) toepassen op 2 decimalen (cent), tenzij een expliciet ander rondingsschema per kostenblok geconfigureerd is.

**Componenten & gedragstags**

- **FR-009**: Systeem MOET elke `fact_looncomponent` rij classificeren via de gedragstags op `dim_looncomponent` (`rsz_plichtig`, `is_werkgeverskost`, `telt_voor_vakantiegeld`, `telt_voor_mu`). De cascade MOET deze tags lezen — nooit hardcoded logica op `component_id` of `familie` bevatten (Principe II).
- **FR-010**: VAA-componenten (bv. `bedrijfswagen_vaa`) MOETEN uitgesloten worden van werkgeverskost-totaal (per `is_werkgeverskost=false`), terwijl TCO-componenten (`bedrijfswagen_tco`) MOETEN worden meegeteld.

**Uurloon-derivatie (T-023)**

- **FR-011**: Systeem MOET het uurloon per contract-periode afleiden als pure functie van (maandloon, gemiddelde_wekelijkse_uren uit param_arbeidsduur). Deze functie MOET zonder side-effects werken en identieke output produceren voor identieke input.

**μ-derivatie (T-024)**

- **FR-012**: Systeem MOET μ = Q/S per contract-periode afleiden als pure functie van (fact_prestatie somuren, param_arbeidsduur.gemiddelde_wekelijkse_uren voor de gemapte pc_id). Componenten met `telt_voor_mu=false` (bv. tijdelijke urenvermindering) MOETEN NIET meetellen in Q.

**Scenario-support**

- **FR-013**: Elke cascade-run MOET expliciet gekoppeld zijn aan een `scenario_id` (uit dim_scenario). Meerdere runs op dezelfde (contract, periode) met verschillende scenario_id's MOETEN naast elkaar kunnen bestaan in `fact_loonkost` zonder exclusion-conflict.

**Testbaarheid (Principe V)**

- **FR-014**: Elke pure functie (uurloon, μ, round_final, kostenblok-berekeningen) MOET test-first geschreven zijn — bijbehorende pgTAP/unit tests MOETEN bestaan vóór de implementatie code.
- **FR-015**: Het systeem MOET een test-suite bevatten met referentiescenarios uit de RSZ-instructiegids (T-029) waarbij minimaal 5 verschillende contract-profielen (bediende cat 1, arbeider cat 1, arbeider cat 3, contract met bedrijfswagen, contract met doelgroepvermindering) resulteren in cascade-output binnen €0.01 tolerantie van het brochure-referentiebedrag.

**Foutmodes**

- **FR-016**: Als een cascade-input onvolledig is (bv. contract heeft geen fact_prestatie voor de periode, of dim_pc rij ontbreekt), MOET de cascade weigeren te draaien en een expliciete fout terugsturen met welke input mist. Er MOGEN geen NULL-cascades zijn.
- **FR-017**: Als een RSZ-grondslagcap (bv. CAO 90) overschreden wordt door de input, MOET de cascade het overschot correct alloceren volgens de PDF Laag 2 regels — niet stilzwijgend cappen.

### Key Entities *(include if feature involves data)*

- **fact_looncomponent**: één rij per (contract, periode, component, scenario). Bevat het bedrag van een specifieke loonvorm (basisloon, premies, extralegaal). Wordt via `dim_looncomponent.gedragstags` behandeld door de cascade.
- **fact_prestatie**: één rij per (contract, periode, prestatiecode, scenario). Bevat gewerkte uren + dagen per prestatiecode (normaal, tijdelijke urenvermindering, overuren). Input voor μ = Q/S en overloon-berekening.
- **fact_wagen**: één rij per (contract, periode, scenario). Bevat catalogus_waarde, co2_g_km, brandstoftype, aanschaffingsdatum voor VAA + CO2-solidariteitsbijdrage berekening.
- **fact_loonkost**: OUTPUT-tabel, één rij per (contract, periode, kostenblok, scenario). Bevat het afgeronde bedrag per kostenblok. AFGELEID — nooit handmatig geïnserteerd.
- **dim_scenario**: catalogus van scenarios per legale entiteit. `kind` in (actual, what_if, forecast, baseline). Elke cascade-run gebruikt exact één scenario_id.
- **Cascade-context**: virtueel entity die per run de (contract_id, periode, scenario_id, snapshot_batch_id) input samenbrengt. Bepaalt welke parameters gelezen worden.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: **Correctheid via referentiescenarios** — de cascade produceert loonkost-output die voor 100% van de RSZ-brochure referentiescenarios (T-029, minimaal 5 profielen) binnen €0.01 tolerantie ligt van het gepubliceerde bedrag.
- **SC-002**: **Determinisme** — 100% van de cascade-runs met identieke (input feiten, snapshot_batch_id) input produceren byte-identical output over onbeperkt aantal herhalingen (Constitution Principe III MUST).
- **SC-003**: **Ontkoppeling parameters van code** — 0 hardcoded numerieke tarieven/plafonds in cascade-code. Elke wijziging aan tarieven (bv. jaarwisseling 2025) is een parameter-import zonder code-wijziging.
- **SC-004**: **Test-first coverage** — 100% van de pure functies (uurloon, μ, round_final, kostenblok-berekeningen) heeft bijbehorende tests met commit-tijdstamp EERDER dan of GELIJK aan de implementatie-commit.
- **SC-005**: **Cascade-transparantie** — 100% van de `fact_loonkost` output-rijen bevat een traceable link naar de originating `snapshot_batch_id` én `scenario_id`, zodat elke bedrag reconstrueerbaar is.
- **SC-006**: **Foutmode-explicitheid** — 100% van de missing-parameter of missing-fact scenarios resulteren in een expliciete gestructureerde fout (welke tabel, welke periode) i.p.v. stille NULL-propagatie.
- **SC-007**: **AFGELEID-invariant** — 0 mogelijkheid tot handmatige INSERT/UPDATE op `fact_loonkost` behalve via de canonieke cascade-uitvoering (geverifieerd door pgTAP negative test).
- **SC-008**: **Pro-rata correctheid μ vs fte_breuk** — 100% van de contract-scenarios met effectieve tijdelijke urenvermindering (fte_breuk ≠ μ) produceren pro-rata verminderingen geschaald met μ, gevalideerd door minimaal 2 referentiescenarios.

## Assumptions

- **Domein scope BE-only**: cascade dekt Belgische werkgeverskost-berekening voor 2024 baseline. Andere landen (Duitsland, Nederland) vallen buiten POC-scope (idem ISS-031 land_id gap).
- **Parameter-data is voor-gesnapshot**: cascade neemt `snapshot_batch_id` als input parameter. De import van tarieven (T-018/T-019/T-020) en de audit-snapshot (T-021) zijn voltooid vóór eerste cascade-run.
- **Facts zijn immutable**: `fact_looncomponent`, `fact_prestatie`, `fact_wagen` worden niet retroactief gewijzigd. Als een correctie nodig is, wordt een nieuw scenario aangemaakt.
- **Single-tenant per contract**: cascade werkt per contract; multi-contract aggregatie is out-of-scope (komt in Phase 6 loonkloof-mart).
- **UI is out-of-scope**: cascade is een backend-service (SQL functies + views); simulator UI komt in Phase 7.
- **Overloon-detectie via prestatiecode**: overuren worden herkend aan `dim_prestatiecode` gedragstag `toeslag_pct`; cascade telt overloon apart in RSZ-grondslag zonder speciale prestatiecode-lookup.
- **Vakantiegeldkas voor arbeiders**: vakantiegeld voor arbeiders wordt niet direct door de werkgever betaald maar via de vakantiekas; cascade telt de 15.38%-bijdrage aan de vakantiekas als werkgeverskost, niet het uitgekeerde bedrag.
- **Bedrijfswagen fiscaal-CO2 berekening**: gebruikt de CO2-formule uit `param_wagen_mobiliteit.co2_formule_json` (T-020). Cascade parseert de formule en past ze toe met minimum-cap uit `minimumbijdrage`.
- **CAO 90 jaarplafond**: cascade past `param_plafond` toe waar `bijdragetype = 'cao90'`. Overschrijding wordt correct her-alloceerd als bruto (niet extralegaal).
- **Test-executie via pgTAP**: alle tests draaien via de bestaande pgTAP infrastructure. ISS-030 (missing test-helper extensie) blijft blokkerend voor lokale runs maar valt buiten deze feature-scope.
- **Determinisme afhankelijk van Postgres-versie**: floating-point/decimal arithmetic gedraagt zich deterministisch mits Postgres 15+ en `numeric(18,4)` cent-precisie strikt gerespecteerd worden.

## Dependencies

- **T-018/T-019/T-020 (parameter-imports)**: cascade heeft concrete 2024 tarieven nodig; POC-baseline is voldoende voor referentiescenarios.
- **T-021 (audit-snapshot)**: `create_parameter_snapshot()` levert de `snapshot_batch_id` die de cascade nodig heeft voor reproduceerbaarheid.
- **Bestaande dim_* tabellen (T-006 t/m T-013)**: contract, componenten, prestatiecodes, PC, land, legale entiteit, sz_behandeling.
- **Constitution v1.0.1**: alle 5 principes zijn bindend voor de cascade-implementatie.
- **RSZ-instructiegids 2024**: als referentiebron voor T-029 integration tests.

## Out-of-Scope

- Multi-contract aggregatie of loonkloof-analyse (Phase 6).
- Simulator UI (Phase 7).
- Multi-country berekening (Duitsland, Nederland — ISS-031).
- Historische jaargangen 2015-2023 (N-004 undecided).
- Aangifte-integratie (DMFA, Dimona) — cascade is berekening, geen indiening.
- Real-time cascade via API (POC gebruikt SQL functie-invocaties; edge function/REST komt later indien nodig).
- Optimistic concurrency op fact_loonkost (single-run assumptie voor POC).
- User-facing error messages (systeem geeft technische fouten; UI-vriendelijk komt met simulator).
