# 5. Data model

Dimensie/fact-structuur behouden uit POC, met specifieke aanpassingen:
tenant-id op alle tenant-scoped tabellen, universele effective-dating,
en full-fidelity snapshots per scenario.

Voordat we naar de individuele beslissingen kijken, expliciet welk
domein-model onder de blueprint ligt. Dit is context die door de rest
van dit hoofdstuk en door hoofdstuk 3 (cascade) heen loopt.

---

## Domein-model: populatie, scenario, outcome, trace

Vier concepten die je uit elkaar wilt houden.

### Populatie

De set contracten van een tenant op een gegeven moment. Wie werkt daar,
op welke functie, sinds wanneer, met welk contract-type. Technisch:
rijen in `dim_contract` met bijhorende `dim_persoon`, `dim_functie`,
`dim_legale_entiteit`.

Populatie is temporeel (contracten hebben `valid_from`/`valid_to`), dus
"de populatie op 15 juni 2026" is een point-in-time query op die
temporele data.

### Baseline scenario

Een scenario dat de *huidige realiteit* van salarissen representeert
voor die populatie. Wie krijgt hoeveel bruto, welke extralegale
voordelen, welke wagen. Technisch: een rij in `dim_scenario` met
`kind='baseline'`, plus bijhorende `fact_looncomponent`-rijen die de
daadwerkelijke lonen bevatten.

Elke tenant heeft exact één baseline. Dat is per definitie de "wat wij
nu betalen"-set.

### What-if scenarios

Aanvullende scenarios die een variant zijn op de baseline: "wat als
iedereen 5% opslag krijgt", "wat als sales-team elektrische wagens
krijgt", "wat als we drie nieuwe engineers aannemen".

Technisch: een rij in `dim_scenario` met `kind='what_if'` of
`'projection'`, plus bijhorende `fact_looncomponent`-rijen die van
baseline zijn *gekopieerd en dan gemuteerd*. Voor een 5%-opslag-scenario
betekent dat: elke baseline-loonrij wordt gekopieerd, `bedrag`-veld
wordt × 1.05.

Een what-if scenario kan verwijzen naar een specifieke baseline (via
`parent_scenario_id`) zodat de derivation-trail zichtbaar blijft.

### Cascade outcome

Per contract, per periode, per scenario: de doorgerekende cijfers.
Bruto, patronale RSZ, doelgroepverminderingen, vakantiegeld,
bedrijfswagen-CO2-bijdrage, arbeidsongevallenverzekering, totaal
werkgeverskost, TCO.

Dit is wat de cascade-executor (hoofdstuk 3) produceert wanneer je
hem aanroept met `(populatie, scenario, periode)`.

### Cascade trace

Naast de outcome levert elke cascade-uitvoering een trace: welke stap
gaf welke output, welke stap werd geskipped en waarom (bijvoorbeeld
non-cumulatie), welke formule werd aangeroepen, welke input werd
gegeven.

Trace is het "waarom"-antwoord bij een specifieke berekening. Voor
audit onmisbaar.

---

## Wat bewaren we, wat berekenen we

| Concept | Bewaard? | Waar |
|---|---|---|
| Populatie (contracten, personen, functies) | Ja | `dim_contract`, `dim_persoon`, `dim_functie` |
| Baseline scenario | Ja | `dim_scenario` + `fact_looncomponent` |
| What-if scenarios | Ja | idem, met kopie + mutaties |
| Scenario snapshot (frozen parameters + cascade-definitie) | Ja | `scenario_snapshots` |
| Cascade outcome (de cijfers) | Nee, tenzij metrics zeggen anders | live-berekend on-demand |
| Cascade trace | Ja | `cascade_run_trace` |

Belangrijk onderscheid: outcome bewaren we niet, trace wel.

### Waarom scenarios bewaren, outcomes niet

Een scenario is een intentie: "wij besloten dit door te rekenen". Die
intentie verdient permanent behoud, ongeacht of iemand het resultaat
nu bekijkt. Het scenario is de bron; de outcome is een afgeleide.

Een outcome is een berekening. De berekening kan altijd opnieuw op basis
van `scenario_id` + `snapshot` + `periode`. Voor kleine tenants is dat
milliseconden — geen argument voor cache. Voor grote tenants komt cache
in beeld, maar de cache is dan een optimalisatie, niet een correctness-
vereiste. De outcome is bit-exact afleidbaar uit de bron.

Trace bewaren we omdat "waarom is stap 4 nul voor dit contract" een
audit-vraag is die je later nog wil kunnen beantwoorden zonder de
exacte cascade-executor in productie te hoeven draaien voor dat oude
tijdstip. Trace is het reconstructie-artefact.

Deze scheiding matcht principe 4 uit hoofdstuk 1 (metrics-driven
caching): we cachen niet de outcome vooraf, we bewaren wat nodig is om
hem exact opnieuw te produceren.

---

## Voorbeeld-flows

### Populatie-pagina bekijken

Accountant zit op populatie-pagina met scenario "Baseline 2026" en
periode "juni 2026":

1. Server component roept cascade-executor aan voor elk contract in de
   populatie
2. Executor leest `fact_looncomponent` voor scenario-baseline, past de
   cascade-DAG toe, produceert outcome + trace per contract
3. Outcome wordt getoond in de UI
4. Trace wordt weggeschreven naar `cascade_run_trace`
5. Volgende visit: cascade wordt opnieuw uitgevoerd (of gecached als
   metrics dat rechtvaardigen), trace wordt aangevuld

### Nieuw scenario aanmaken

Accountant klikt "Nieuw scenario: iedereen 5% opslag":

1. Server action roept `create_scenario_with_snapshot` RPC aan
2. Nieuw `dim_scenario`-record wordt aangemaakt met `kind='what_if'` en
   `parent_scenario_id` verwijzend naar de baseline
3. Baseline `fact_looncomponent`-rijen worden gekopieerd naar het nieuwe
   scenario_id, met de opslag-mutatie toegepast (bedrag × 1.05 voor
   basisloon-componenten)
4. `scenario_snapshots` bevat de frozen parameter-context: welke
   RSZ-tarieven, welke doelgroepverminderingen, welke cascade-definitie
   geldig waren op dit moment
5. Bij bekijken van dit scenario: cascade-executor rekent met de nieuwe
   fact-rijen én met de frozen snapshot uit stap 4

### Historische scenario herbekijken

Accountant kijkt in oktober 2028 naar een scenario dat in juli 2026 was
aangemaakt:

1. Executor leest `scenario_snapshots.param_data` — de RSZ-tarieven
   zoals ze in juli 2026 waren, niet zoals ze nu zijn
2. Executor leest `scenario_snapshots.cascade_definition_data` — de
   cascade-DAG zoals hij in juli 2026 was
3. Uitvoering gebeurt tegen deze frozen context, waardoor het bit-
   exacte antwoord uit juli 2026 wordt gereproduceerd

Zonder de snapshot zou de executor met de huidige RSZ-tarieven werken
en een ander antwoord geven — reproduceerbaarheid gebroken.

---

Dit domein-model is de context waarbinnen de rest van de blueprint-
beslissingen leven. Elke technische keuze in de rest van dit hoofdstuk
en in hoofdstuk 3 (cascade-DAG) is ontworpen om dit model correct te
ondersteunen.

---

## Beslissing 1: Dim/fact/param-structuur behouden

### Beslissing

De Kimball-stijl dimensie/fact-modellering uit de POC wordt behouden:
dimensie-tabellen voor entiteiten (personen, contracten, functies,
legale entiteiten), fact-tabellen voor gebeurtenissen (looncomponenten,
prestaties, wagens), en parameter-tabellen voor referentiedata (RSZ-
tarieven, doelgroepverminderingen).

### Waarom

Deze modellering is industry-standard voor analytisch-heavy applicaties.
Payroll-cascade is analytisch: berekeningen aggregeren fact-data via
dimensie-lookup en parameters. Kimball past.

Alternatieve modelleringen (puur genormaliseerd of documenten-databases)
zouden vertraging opleveren zonder duidelijke winst.

### Alternatieven overwogen

**Volledig genormaliseerd (3NF).** Werkt maar joins voor elke query zijn
duur. Voor OLAP-workload zoals hier niet passend.

**Documenten-database (denormalized JSON per contract).** Snel lezen
maar update-anomalieen bij parameter-wijzigingen. En Postgres-native
Kimball is efficiënter.

### Trade-off

Kimball vereist discipline om dimensie- en fact-tabellen consistent te
onderhouden. Refactoring van de structuur is significant werk.

Voor het domein levert dit een natuurlijke, queryable structuur.

### POC-bewijs

De POC-structuur (dim_persoon, dim_contract, fact_looncomponent, etc.)
werkte prima voor alle cascade-berekeningen. Geen structurele bugs; wel
enkele kleinere issues (zoals ontbrekende tenant-kolom, zie beslissing 2).

---

## Beslissing 2: tenant_id op alle tenant-scoped tabellen (denormaliseren)

### Beslissing

Elke tenant-scoped tabel heeft een directe `tenant_id` kolom. Ook fact-
tabellen die van nature via contract-join het tenant kunnen bepalen,
krijgen de kolom direct.

### Waarom

In de POC hadden `fact_looncomponent`, `fact_prestatie` en `fact_wagen`
geen directe tenant-kolom. Tenant werd afgeleid via
`fact_* → contract → legale_entiteit → owning_account`. Dit werkte
functioneel voor RLS maar had drie nadelen:

- RLS-policies moesten complexer worden (drie-tabel-join in de policy)
- Cache-invalidation-triggers moesten dezelfde joins doen — traag bij
  grote fact-tabellen
- Analytics-queries per tenant deden altijd overbodige joins

Denormalisatie kost ~16 bytes per rij extra, wat op grote schaal
significant is maar niet significant genoeg om deze eenvoud op te
geven.

### Alternatieven overwogen

**Geen denormalisatie, tenant via join.** De POC-aanpak. Werkt maar
gevens toe aan alle RLS-policies en queries. Bij groei tot honderden
miljoenen rijen wordt de join-overhead noemenswaardig.

**Partial denormalisatie: alleen op high-traffic tables.** Beetje meer
werk om welke tabellen wel/niet, en creëert inconsistentie in het model.

### Trade-off

Extra storage per rij (klein). Extra discipline: bij insert moet
tenant_id worden meegegeven of via trigger uit contract worden gehaald.

Winst: eenvoudiger RLS-policies, snellere queries, cache-triggers
zonder joins, cross-tenant lek onmogelijk zelfs bij join-fouten.

### POC-bewijs

Cache-invalidation-triggers uit ISS-089 moesten voor fact_* via join
naar dim_contract → dim_legale_entiteit — extra query per rij. Met
directe tenant_id was dit één simpele filter.

---

## Beslissing 3: Universele effective-dating op temporeel-relevante tabellen

### Beslissing

Elke tabel met tijd-gebonden semantiek krijgt `valid_from` en `valid_to`
kolommen. Wijzigingen zijn nieuwe rijen, niet updates. Point-in-time
queries via range-filter.

### Waarom

Belgische payroll heeft veel temporele data: RSZ-tarieven wijzigen
jaarlijks, contracten wijzigen bij salarisrondes, functienamen wijzigen
bij reorganisaties. Zonder effective-dating verlies je historie zodra
je een update doet.

Effective-dating is de canonieke oplossing (Snodgrass 1999, Fowler 1996).
Consistent toepassen voorkomt inconsistenties tussen tabellen.

### Alternatieven overwogen

**Audit-tabel per hoofdtabel.** Wijziging → oude row naar audit-tabel,
nieuwe row in hoofd. Werkt maar dubbelt schema en vraagt custom query
voor historische reads.

**System-versioned tables (SQL:2011).** Postgres heeft dit niet native
(wel via extensies). Voor consistentie met de rest van het model:
handmatige effective-dating met valid_from/valid_to is werkbaar.

**Alleen op parameters, niet op operationele data.** Half-half. Zorgt
voor inconsistentie ("waarom is contract muteerbaar, RSZ-tarief niet?").
Consistent toepassen is duidelijker.

### Trade-off

Extra kolommen op elke temporeel-relevante tabel. Queries moeten altijd
een periode-filter meenemen. Bij niet-doen krijg je de allernieuwste
row per unieke business-key.

Winst: volledige historie behouden, point-in-time queries mogelijk,
audit-trail als natuurlijk gevolg.

### POC-bewijs

POC gebruikte effective-dating consistent voor parameters en contracten.
Werkte goed. Geen bugs, alleen aanleiding tot conventie-discipline.

---

## Beslissing 4: Full-fidelity snapshot per scenario

### Beslissing

Bij aanmaak van elk scenario worden de op dat moment geldige parameter-
rijen en cascade-definitie letterlijk gekopieerd naar een
`scenario_snapshot` tabel als jsonb. Herberekening van dat scenario
gebruikt de snapshot, niet de live tabellen.

### Waarom

Zie principe 3 uit hoofdstuk 1. Kortweg: reproduceerbaarheid over jaren
vereist dat de exacte context van berekening wordt bewaard, niet alleen
een referentie ernaar.

### Alternatieven overwogen

Zie hoofdstuk 1 principe 3 voor het volledige alternatieven-overzicht
(semantic reference, event-sourcing, geen snapshot).

### Trade-off

Storage per snapshot: enkele KB voor Belgische parameters. Bij 100.000
scenarios praten we over honderden MB tot een GB. Op modern DB
verwaarloosbaar. Executor-complexiteit: moet snapshot lezen ipv live
tabellen.

Winst: elke scenario blijft draaien zoals bij creatie, ongeacht
parameter-wijzigingen daarna.

### POC-bewijs

Zie hoofdstuk 1 principe 3.

---

## Beslissing 5: Time-series data (audit, trace) partition door tijd

### Beslissing

Tabellen die per unit-time groeien (audit_log, cascade_run_trace,
activity_log) worden gepartitioneerd op timestamp met maand-granulariteit
via pg_partman.

### Waarom

Audit-log kan bij middelgrote scale tientallen miljoenen rijen per jaar
worden. Ongepartitioneerd wordt elke query traag (index-scans over
volledig groeiende tabel). Partitionering per maand houdt actieve
partitions klein en maakt archivering triviaal (oude partitions naar
S3, drop partition uit hoofdtabel).

pg_partman automatiseert het maand-per-maand aanmaken en oude
partitions droppen op basis van retention-beleid.

### Alternatieven overwogen

**Manuele partition management.** Werkt maar vergt operationele
discipline. pg_partman is voor deze use case exact ontworpen.

**Geen partitionering, indices only.** Werkt tot een paar honderd
miljoen rijen. Daarna zwaar. Preventief partitioneren is goedkoop.

**Externe tijd-serie database (Timescale, InfluxDB).** Overkill voor
audit-workload. Postgres partitioning + retention volstaat.

### Trade-off

Extra extensie (pg_partman) om te beheren. Kleine complexiteit-toename
bij deploy.

Winst: audit-log blijft snel query-baar, archivering is triviaal, geen
"onze audit-tabel is 200GB en breekt onze backups" moment.

### POC-bewijs

POC had geen partitionering. Voor POC-schaal geen probleem. Vroeg
inbouwen is preventief werk dat later duur wordt (partition-add op
grote levende tabellen is uitdagend).

---

## Beslissing 6: Type-generatie voor TypeScript-integratie

### Beslissing

`supabase gen types typescript` wordt onderdeel van de CI. Gegenereerde
types leven in `packages/db-schema/types.ts` en worden bij elk
schema-wijziging opnieuw gegenereerd.

### Waarom

Handmatig types onderhouden aan de client-kant leidt tot drift. `as
unknown as PopRow[]` casts (ISS-097 in POC) waren symptoom. Gegenereerde
types die exact het DB-schema spiegelen elimineren deze drift.

### Alternatieven overwogen

**Handmatig types onderhouden.** Werkt maar wordt drift-bron.

**ORM-generated types (Drizzle, Kysely).** Krachtiger want ook query-
builder-types. Nadeel: ORM als extra laag; Supabase-client integreert
naadloos met gegenereerde types.

### Trade-off

Type-generatie in CI is één extra stap. Bij mislukking (bijvoorbeeld
Supabase CLI offline) breekt de build.

Winst: end-to-end type-safety van DB naar frontend, geen casts nodig.

### POC-bewijs

ISS-097 was direct gevolg van niet-gebruikte typegen. Types leefden
handmatig in `row-detail-sheet.tsx` en werden ge-cast met `as unknown as`.

---

## Verband met andere hoofdstukken

- Security-model (hoofdstuk 4) leunt op tenant_id-kolommen voor RLS
- Cascade DAG (hoofdstuk 3) benut effective-dating van parameters
- Caching (hoofdstuk 6) gebruikt tabel-versie-hashes uit fact-data
- Operations (hoofdstuk 11) werkt partition-management en retention
  verder uit
