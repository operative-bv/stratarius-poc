<!--
SYNC IMPACT REPORT
==================

Version change: — → 1.0.0 (initial ratification)
Bump rationale: Fresh adoption; no prior version to compare against.

Principles added (all NEW):
  I.   Effective-Dating Everywhere (NON-NEGOTIABLE)
  II.  Data-Driven Behavior, No Hardcoded Logic
  III. Strict Separation of Parameters, Facts, and Logic
  IV.  Two Fractions, Never Conflated
  V.   Test-First for the Calculation Cascade (NON-NEGOTIABLE)

Sections added:
  - Schema Naming Conventions
  - Domain, Compliance & Sources
  - Development Workflow & Quality Gates
  - Governance

Naming convention (ratified):
  - Narrative language: Nederlands.
  - Domein-tabellen en -kolommen (payroll, Belgisch-specifiek, alles wat het
    conceptueel datamodel dekt): Nederlands, lowercase snake_case, matcht de
    PDF-terminologie. Voorbeelden: dim_looncomponent, fact_prestatie,
    param_doelgroepvermindering, sz_behandeling_id, geldig_van, fte_breuk.
  - Infrastructuur-tabellen (auth, accounts, invitations, billing — geërfd van
    Basejump): Engels, ongewijzigd.
  - Belgische regulatory acroniemen (rsz, pc, kbo, bv, riziv, rva, vte, fod, cao,
    sz): kept canoniek in zowel narratief als schema.

Templates status:
  - .specify/templates/plan-template.md — no template change needed; Constitution
    Check gate is filled per-plan against Principles I–V.
  - .specify/templates/spec-template.md — no template change needed; principles
    constrain content, not shape.
  - .specify/templates/tasks-template.md — ⚠ known tension: default "Tests are
    OPTIONAL" conflicts with Principle V for features touching the calculation
    cascade or parameter layer. Handled by the Test-verplichting override in
    the Development Workflow section (per-feature override in the spec is
    required).
  - .specify/templates/checklist-template.md — no change needed.

Runtime guidance:
  - README.md — Basejump onboarding, no change.
  - _supporting-material/Datamodel_werkgeverskost_Belgie.pdf — bindende
    domein-referentie tot vertaald naar Supabase-migraties en data-model.md per
    feature.

Deferred items:
  - None.
-->

# Stratarius Constitution

Stratarius is een POC voor de berekening van Belgische werkgeverskost (loonkost, TCO,
loonkloof) die schaalt van een enkelvoudige simulator naar een volledige populatie. Deze
constitution codificeert de niet-onderhandelbare architectuur- en werkprincipes die iedere
feature-spec, plan en implementatie in dit project respecteert.

## Core Principles

### I. Effective-Dating Everywhere (NON-NEGOTIABLE)

Elke parameter, elk tarief, elk plafond en elk contract draagt een geldigheidsinterval.
Bestaande rijen worden NOOIT overschreven; een wijziging is ALTIJD een nieuwe rij.
Koppeling tussen feiten en parameters gebeurt via een temporele join (periode ∈
geldigheid), NOOIT via harde foreign keys naar parameterrijen.

- **MUST**: elke tabel in de parameterlaag (`param_*`) en `dim_contract` bevat
  `geldig_van date NOT NULL` en `geldig_tot date NULL` (NULL = open einde).
- **MUST**: uitgestelde wetgeving is toegestaan — `geldig_van > current_date` is geldig
  en de rekencascade MOET dit ondersteunen (forecasting).
- **MUST NOT**: geen `UPDATE` op parameterrijen buiten typo-fixes; wetswijzigingen zijn
  `INSERT` van een nieuwe rij plus `UPDATE geldig_tot` op de voorganger.

**Rationale**: Belgische loonwetgeving wijzigt mid-year (indexaties, nieuwe CAO's,
aangepaste doelgroepverminderingen). Overschrijven corrumpeert historische én
forecasting-berekeningen. De temporele architectuur is de enige manier om "wat kostte
deze werknemer in Q3 2024?" reproducerbaar te beantwoorden.

### II. Data-Driven Behavior, No Hardcoded Logic

`dim_looncomponent` en `dim_prestatiecode` dragen hun fiscaal en sociaal gedrag als
attributen (`rsz_plichtig`, `is_werkgeverskost`, `telt_voor_vakantiegeld`,
`sz_behandeling_id` FK, `telt_voor_mu`, `gelijkgesteld_rsz`,
`gelijkgesteld_vakantiegeld`, `betaalbron`). De rekenlaag weet NIET wat een component
of prestatiecode heet — enkel hoe het zich gedraagt.

- **MUST**: nieuwe loonvormen (bv. cafetariaplan-item, mobiliteitsbudget-variant, nieuwe
  extralegale voordeel-categorie) worden toegevoegd als rij met correcte gedragstags.
  Geen code-wijziging, geen migratie voor gedrag.
- **MUST NOT**: geen `if component_code == 'XYZ'` of `switch (prestatiecode)` in de
  rekencascade. Rekencascade leest gedragstags, niet identiteit.

**Rationale**: Belgische loontypologie evolueert (cafetariaplannen, mobiliteitsbudget,
warrants, ecocheques). Elke nieuwe vorm code-wijziging vereisen maakt het systeem
breekbaar en de release-cadans onhoudbaar. Data-gedreven gedrag maakt uitbreiding een
SQL-insert.

### III. Strict Separation of Parameters, Facts, and Logic

Drie strikt gescheiden lagen dragen samen de rekencascade:

- **Parameterlaag** (`param_rsz`, `param_structurele_vermindering`,
  `param_doelgroepvermindering`, `param_arbeidsduur`, `param_vakantiegeld`,
  `param_bijzondere_bijdragen`, `param_sectorbijdrage`, `param_extralegaal`,
  `param_wagen_mobiliteit`, `param_index`, `param_plafond`) — tarieven, plafonds,
  coëfficiënten. Effective-dated. Geen bedragen elders in het systeem.
- **Feitenlaag** (`fact_looncomponent`, `fact_prestatie`, `fact_wagen`) — de
  gebeurtenissen per contract × periode. Puur input.
- **Rekencascade** — pure functies die feiten × parameters transformeren naar
  `fact_loonkost` en `mart_loonkloof`. Geen bedragen, geen tarieven, geen tijdvakken
  in de code zelf.

- **MUST**: één tariefwijziging = één rij in de parameterlaag. Geen tweede plek waar
  hetzelfde tarief kan worden gewijzigd.
- **MUST**: rekencascade is deterministisch en bij-effectvrij — gegeven identieke input
  feiten en parametersnapshot, identieke output.
- **MUST NOT**: geen bedragen als constanten in TypeScript, SQL of migraties. Geen
  tarief-lookups buiten de parameterlaag.

**Rationale**: als bedragen in code kunnen zitten, verandert een tariefaanpassing van
"één rij toevoegen" naar "PR, review, deploy, herrekening, snapshot". Elke laag
onafhankelijk verifieerbaar tegen brondocumenten (RSZ-brochure, PC-CAO,
RVA-omzendbrief).

### IV. Two Fractions, Never Conflated

`fte_breuk` (juridische tewerkstellingsbreuk op `dim_contract`) en `mu` (effectieve
prestatiebreuk μ = Q/S, afgeleid uit `fact_prestatie`) worden ALTIJD gescheiden
bijgehouden en toegepast:

- `fte_breuk` normaliseert de **beloning** (bruto → uurloon → loonkloof).
- `mu` drijft de **RSZ-kost en verminderingen** (pro rata).

Bij tijdskrediet: `fte_breuk = 1`, `mu < 1`. Bij deeltijds contract: `fte_breuk < 1`,
`mu = fte_breuk`. Beide bevestigen dat één breuk twee werelden niet kan bedienen.

- **MUST**: elke berekening documenteert in code én in tests welke breuk gebruikt wordt
  en waarom.
- **MUST NOT**: geen aggregatie, substitutie of `coalesce` van `fte_breuk` door `mu` of
  omgekeerd.

**Rationale**: verlies van dit onderscheid corrumpeert zowel loonkloof-analyse
(verkeerd genormaliseerd uurloon) als RSZ-berekening (verkeerde pro rata
verminderingen). Dit is de subtielste bug-bron in Belgische loonberekening; expliciet
maken voorkomt regressies.

### V. Test-First for the Calculation Cascade (NON-NEGOTIABLE)

Elke stap van de 9-stappen rekencascade (bruto → RSZ-grondslag → basis patronale RSZ →
structurele vermindering → doelgroepverminderingen → bijzondere bijdragen → provisies →
extralegale voordelen → wagen & mobiliteit → arbeidsongevallenverzekering → TCO) heeft
**unit tests met officiële voorbeeldberekeningen** vóórdat productiecode geschreven
wordt. Red → Green → Refactor strikt afgedwongen.

- **MUST**: elke rekencascade-stap heeft minstens één test per werkgeverscategorie
  (1/2/3), per tijdvak dat een tariefwijziging omvat, en per grensgeval (deeltijds,
  tijdskrediet, moederschapsrust, tijdelijke werkloosheid).
- **MUST**: testcases citeren de bron (RSZ-brochure sectie, PC-CAO artikel,
  RVA-omzendbrief, KB) in de testnaam of comment.
- **MUST NOT**: geen implementatiecode voor de rekencascade zonder falende test eerst.

**Rationale**: fouten in loonberekening leiden tot juridische aansprakelijkheid en
klantvertrouwensbreuk. Regressies bij wetswijzigingen (nieuwe indexatie, aangepaste
doelgroepvermindering) worden alleen betrouwbaar gevangen door testcases die de
brondocumenten reflecteren.

## Schema Naming Conventions

Deze conventie is bindend voor alle nieuwe Supabase-migraties en refactors:

**Domein-schema (Nederlands)** — alles wat het conceptueel datamodel dekt (payroll,
Belgische regulering, loonkloof-analyse):

- Tabelnamen matchen de PDF (lowercase snake_case): `dim_persoon`, `dim_contract`,
  `dim_functie`, `dim_legale_entiteit`, `dim_looncomponent`, `dim_prestatiecode`,
  `dim_sz_behandeling`, `dim_land`, `dim_hierarchie`, `bridge_hierarchie`,
  `map_entiteit_pc_competentie`, `fact_looncomponent`, `fact_prestatie`, `fact_wagen`,
  `fact_loonkost`, `mart_loonkloof`, en de volledige `param_*` reeks
  (zie Principe III).
- Kolomnamen: `geldig_van`, `geldig_tot`, `fte_breuk`, `mu`, `rsz_plichtig`,
  `is_werkgeverskost`, `telt_voor_vakantiegeld`, `telt_voor_mu`, `gelijkgesteld_rsz`,
  `gelijkgesteld_vakantiegeld`, `betaalbron`, `sz_behandeling_id`,
  `werkgeverscategorie`, `bron_url`, `bron_document`.
- Persoons-attributen op `dim_persoon`: `geslacht`, `geboortedatum`,
  `opleidingsniveau`.

**Infrastructuur-schema (Engels)** — geërfd van Basejump, ongewijzigd:
`accounts`, `account_user`, `invitations`, `billing_customers`,
`billing_subscriptions`, etc. Nieuwe generieke infrastructuur (audit_log, sessions,
feature_flags) volgt dezelfde Engelse conventie.

**Randgevallen expliciet vastgelegd**:

- `dim_land` (niet `dim_country`) — koppelt aan tariefsets per land, hoort bij het
  domein.
- `dim_org_unit` (Engels) — puur generiek organisatie-hiërarchie concept, geen
  Belgische specificiteit.
- `mu` (kolomnaam) — mathematisch symbool μ, Postgres-portable ASCII.
- `pc_id` — verwijzing naar paritair comité, blijft canoniek `pc`.
- `numeric(18,4)` — SQL literal, Principe III/domein.

**Belgische regulatory acroniemen** die canoniek blijven (nooit vertaald):
`rsz`, `pc`, `kbo`, `bv`, `riziv`, `rva`, `vte`, `fod`, `cao`, `sz`, `vaa`, `fso`,
`bev`.

## Domain, Compliance & Sources

**Bron-hiërarchie voor parameters**: elke rij in de parameterlaag MOET een `bron_url`
of `bron_document`-referentie dragen naar de officiële bron (RSZ, FOD Financiën, RVA,
sector-CAO, KB). Import-scripts halen parameters uit deze bronnen; handmatige overrides
zijn een uitzondering met commentaar in dezelfde commit.

**GDPR & persoonsgegevens**: `dim_persoon` (`geslacht`, `geboortedatum`,
`opleidingsniveau`) is STRIKT gescheiden van `dim_contract`. Beschermde en verklarende
kenmerken horen op de persoon, nooit op het contract. Toegang tot `dim_persoon.geslacht`
en `dim_persoon.opleidingsniveau` is enkel voor loonkloof-analyse (`mart_loonkloof`)
en vereist expliciete rechtsgrondslag per query — geen algemene `SELECT *` buiten
dashboards die dit legitimeren.

**Geldbedragen**: alle bedragen in Postgres als `numeric(18,4)` (vier decimalen voor
centsprecisie in cascade-tussenberekeningen). NOOIT `float`, `double precision`, of
JavaScript `number` voor bedragen. Afronding gebeurt UITSLUITEND bij eindpresentatie
(rapport, factuur, export) via een expliciete afrondingsregel.

**Multi-tenancy**: elke tenant (accountantskantoor of HR-adviseur) ziet enkel eigen
data via Supabase RLS-policies geërfd van Basejump. `legale_entiteit_id`,
organisatie-hiërarchie (`bridge_hierarchie`), contracten en feiten dragen expliciete
tenant-scoping. Cross-tenant queries zijn niet mogelijk zonder service-role bypass,
die enkel in audit- en migratiescripts wordt gebruikt en per gebruik gelogd.

**Scope-grens**: enkel werkgeverskost (werkgevers-RSZ, BV, extralegaal, wagen-TCO).
Netto-loonberekening (werknemers-RSZ, bedrijfsvoorheffing eindafrekening) valt buiten
scope tot expliciete uitbreiding via constitution-amendment.

## Development Workflow & Quality Gates

**Speckit-flow voor domein-logica**: elke feature die de rekencascade, parameterlaag,
`fact_*`-tabellen of `mart_loonkloof` raakt DOORLOOPT `/speckit-specify` →
`/speckit-plan` → `/speckit-tasks` → `/speckit-implement`. Ad-hoc implementatie buiten
deze flow is niet toegestaan voor deze scope. UI-polish,
Basejump-boilerplate-fixes en documentatie mogen sneller.

**Constitution Check gate** (in `/speckit-plan`): elk plan bevestigt expliciet
compliance met alle vijf principes. Overtredingen worden vastgelegd in
`Complexity Tracking` met rechtvaardiging en aanvaard door de gebruiker vóórdat
`/speckit-implement` mag starten.

**Test-verplichting override**: de standaard "Tests are OPTIONAL" in
`.specify/templates/tasks-template.md` geldt NIET voor features die de rekencascade of
parameterlaag raken. Zulke features MOETEN in hun `spec.md` expliciet tests aanvragen
en de gegenereerde `tasks.md` MOET test-taken bevatten vóór implementatie-taken
(Principe V).

**Supabase migrations**: append-only, met timestamp-prefix. Geen `DROP` of destructieve
`ALTER` zonder een tegenmigrations plan met dataterugvalstrategie. Elke migratie
doorloopt lokale `supabase db reset` en integratietests vóór commit.

**Test-categorieën**:

- **Unit tests**: rekencascade-stappen, één per (parameter, tijdvak, casus). Draaien
  lokaal in seconden.
- **Contract tests**: Supabase RPC-signatures en Edge Function inputs/outputs.
- **Integration tests**: rekencascade eind-tot-eind met vaste referentiescenario's
  (gearchiveerde voorbeeldberekeningen).

**Parameter-snapshot audit**: bij elke bulk-parameter-import (bv. jaarwisseling
RSZ-tarieven) wordt een snapshot-commit gemaakt (parameter-diff + bron-URL's) voor
auditbaarheid en reproduceerbaarheid.

## Governance

Deze constitution vervangt alle andere praktijken. Bij conflict met externe
documentatie, boilerplate-conventies (Basejump), of persoonlijke voorkeur wint de
constitution.

**Amendementen**:

- Nieuw principe of materiële uitbreiding van bestaand principe = MINOR bump.
- Verwijdering of herdefinitie van bestaand principe = MAJOR bump.
- Verduidelijking, taalfix, niet-semantische verfijning = PATCH bump.

Elk amendement gebeurt in een aparte PR met een migratie-notitie voor bestaande specs
en (indien van toepassing) migratiescripts voor data.

**Compliance review**: elke `/speckit-plan` MOET de Constitution Check afvinken.
Onopgeloste Constitution violations blokkeren `/speckit-implement`. Elke PR die
domein-logica raakt MOET in de PR-beschrijving expliciet vermelden welke principes zijn
getoetst en, waar relevant, naar welke testcases die verifiëren.

**Runtime guidance**:

- `README.md` — Basejump onboarding en dev-start.
- `_supporting-material/Datamodel_werkgeverskost_Belgie.pdf` — het conceptueel datamodel
  is de bindende domein-referentie tot het is vertaald naar Supabase-migraties en
  `data-model.md` per feature.
- Per-feature: `.specify/specs/NNN-slug/plan.md` bevat de concrete Constitution
  Check-antwoorden voor die feature.

**Version**: 1.0.0 | **Ratified**: 2026-07-03 | **Last Amended**: 2026-07-03
