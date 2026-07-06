# 1. Fundamentele principes

Vijf beslissingen die uit onze POC-lessons voortkwamen en die het
architectuur-fundament vormen. Elke andere hoofdstuk werkt één van deze
uit.

Belangrijk om vooraf te zeggen: deze principes zijn de conclusies uit
een specifiek project — Belgische salaris-cascade voor accountants, met
GDPR-eisen, in een team van één ontwikkelaar met AI-assistentie. Ze
elimineren categorieën bugs die wij tegenkwamen. Voor een ander domein
of team-context kunnen andere principes belangrijker zijn.

De achterliggende structuur: onze POC leverde 16 issues op in twee
review-rondes. Achter elke issue zat een architectuur-beslissing die
vroeg impliciet of niet-expliciet was. Deze vijf principes maken die
beslissingen expliciet.

---

## Principe 1: RPC-only surface — één security-mechanisme

### Beslissing

Alle domein-toegang (reads en writes) gaat via `SECURITY DEFINER` RPCs
met expliciete tenant-parameter. Directe grants op tenant-scoped tabellen
worden geREVOKEd. RLS blijft aan als tweede verdedigingslaag.

### Waarom

De POC gebruikte vier security-mechanismen tegelijk: directe grants,
RLS-policies, SECURITY DEFINER RPCs, en cache-invalidation triggers.
Vier van onze zeven critical bugs kwamen uit de **interacties** tussen
die mechanismen — niet uit de mechanismen zelf.

Bij een enkel mechanisme weet elke reviewer waar de tenant-check zit:
aan het begin van de RPC. Bij vier mechanismen moet je vier plekken
checken plus de interactie ertussen begrijpen.

De concrete emergent bugs:

**ISS-098** liet zien dat RLS filtering-semantiek geeft waar we
guarding-semantiek nodig hadden. `.limit(1)` op een RLS-gefilterde
query gaf een willekeurige toegankelijke rij terug, niet "de rij voor
deze URL". Bij multi-membership users kon een clear-operatie op tenant
A per ongeluk tenant B's data raken.

**ISS-099** was een GDPR-bypass. `dim_persoon.geslacht` had column-REVOKE
voor bescherming van gevoelige data. Maar `mart_loonkloof` repliceerde
`geslacht` in een andere tabel met authenticated SELECT. De REVOKE was
omzeilbaar zonder dat iemand het merkte tot de tweede review-ronde.

**ISS-100** was een aannamefout in cache-triggers. De trigger op
`dim_legale_entiteit` was DELETE-only omdat ik dacht dat INSERT/UPDATE
geen berekening beïnvloedt. Verkeerd: `werkgeverscategorie` en `gewest`
sturen direct de RSZ- en doelgroepvermindering-berekeningen.

**ISS-101** ging over concurrency. Advisory locks in refresh-RPCs
serialiseerden alleen refreshes onderling. Mutation-triggers namen
dezelfde lock niet. Een refresh kon commit'en met stale data terwijl
een mutation net had gedraaid.

Elk van deze vier bugs is een interactie tussen mechanismen. Bij één
mechanisme zijn ze categorisch onmogelijk.

### Alternatieven overwogen

**Basejump-default (RLS + direct grants).** Werkt goed voor apps met één
tenant per user en zonder scherpe GDPR-eisen. Was de POC-keuze. Faalt
zodra multi-membership of column-level PII in beeld komt. Voor productie
met Belgische compliance-eisen niet houdbaar.

**Application-layer authorization (elke query in TypeScript checken).**
Vermindert DB-complexiteit maar vereist enorme discipline in elk stukje
app-code. Elke nieuwe endpoint is een potentiële bug. In review-ronde 2
werd ISS-098 gevonden ondanks dat we RLS hadden — RLS was juist de
reden dat mensen dachten dat het veilig was. Application-only zonder
DB-verdediging is nog fragieler.

**ORM boven Postgres (Prisma of Drizzle).** Verbergt de complexiteit
door Postgres als datalaag te behandelen. Voor payroll-cascade niet
passend omdat je atomicity van berekening naast data verliest. Zou
betekenen dat we de cascade-in-Postgres-keuze uit POC ook opgeven —
grotere afstand van de POC-lessons.

### Trade-off

Elke read en write is een RPC met auth-check, tenant-check, rechtsgrondslag,
en de actual query. Voor het bouwen van elke feature is dat noemenswaardig
meer boilerplate dan direct-query. Discipline om die RPCs consistent te
maken is een team-vaardigheid die je moet aanleren.

Wat je terugkrijgt: één plek per operatie waar de security-context leeft.
Nieuwe teamleden leren het patroon één keer. Een auditor kan de gehele
security-surface reviewen door alle RPC-signatures langs te lopen. Elke
DB-touch heeft automatisch een RPC-naam en rechtsgrondslag, wat de
GDPR-audit-log compleet maakt.

### POC-bewijs

Migration `20260703350000_fix_domain_table_grants.sql` gaf direct
INSERT/UPDATE/DELETE grants aan authenticated. Die grants werkten
functioneel prima tot de review-rondes ISS-089 (directe DML bypasste
cache) en ISS-099 (geen weg om PII column-REVOKE af te dwingen op
afgeleide tabellen) blootlegden.

Zie hoofdstuk 4 voor uitwerking.

---

## Principe 2: Cascade als declaratieve DAG — configuratie ipv code

### Beslissing

De 9-stappen cascade wordt beschreven in een configuratie-tabel en
uitgevoerd door één generieke executor. Compositie, ordening,
non-cumulatie zijn data, niet code.

### Waarom

Belgische payroll-wetgeving is complex maar gestructureerd. Cascade-regels
volgen een consistent patroon: elke stap heeft input, output, positie
in de reeks, en soms non-cumulatie-relaties met andere stappen. Deze
structuur laat zich modelleren.

Twee redenen om deze structuur expliciet in data te zetten:

**Fiscale review zonder Postgres-kennis.** Als een fiscaal-jurist een
wetsupdate wil beoordelen, moet hij de cascade kunnen inzien. In
POC-vorm — 15 migrations met verspreide compositie-logica — is dat
onmogelijk zonder programmeur-tussenkomst. Bij declaratieve tabel:
SELECT * FROM cascade_step_definition en de vraag is beantwoord.

**Cascade-wijzigingen zonder deploy.** Belgische RSZ-tarieven wijzigen
jaarlijks. Doelgroepverminderingen wijzigen bij regeerakkoorden. Als
elke wijziging een code-change vereist, gaat elke wetsupdate door
development-review-deploy cyclus. Bij data-driven cascade: bevoegde
persoon INSERT'et rijen in configuratie-tabel, effective-dating regelt
de rest.

### Alternatieven overwogen

**Procedurele call-chain, de POC-aanpak.** Werkt maar is niet reviewbaar
door niet-technische personen, en niet configureerbaar zonder migration.

**Externe rules-engine zoals Drools of Camunda DMN.** Voor Belgische
payroll overkill: te veel infrastructuur voor een gestructureerd
probleem dat in twee Postgres-tabellen past. Rules-engines lonen bij
duizenden rules over verschillende domeinen. Belgische payroll heeft
ongeveer 30 rules die stabiel zijn.

**Cascade in TypeScript application-layer.** Verliest atomicity met data
en verplaatst berekening weg van de bron. Verlaat de POC-keuze om
cascade in Postgres te houden — die keuze was juist een van de goede
POC-beslissingen.

### Trade-off

Meer upfront ontwerp. Formula-functies moeten een uniform interface
hebben. Debugging via trace-log vraagt gewenning bij ontwikkelaars die
gewend zijn aan stack-traces.

Wat je terugkrijgt: cascade-wijzigingen zonder deploy. Fiscale review
mogelijk door niet-technische reviewer. Trace-log per berekening voor
audit. Effective-dating op cascade zelf.

Belangrijkste risico dat expliciet aandacht vraagt: de executor zal
dynamic SQL gebruiken om formula-functies aan te roepen. Dat is een
SQL-injection-oppervlak als niet correct afgeschermd. Dit is
non-negotiable: formula-namen zijn platform-side-only (REVOKE grants
op configuratie-tabel voor tenant-users), whitelist-check op formule-
naam, en identifier-quoting in EXECUTE. Als deze drie disciplines niet
worden gehandhaafd is de declaratieve architectuur juist gevaarlijker
dan de call-chain.

### POC-bewijs

15 cascade-migraties met verspreide compositie-logica: `cascade_stap*`
files individueel, integration-logica in `cascade_populatie_snapshot`,
non-cumulatie in `cascade_stap4_non_cumulatie.sql`, en drie
"integration"-migraties die de compositie evoluerend aanpasten. Elke
wijziging aan de cascade was een migration.

Zie hoofdstuk 3 voor uitwerking.

---

## Principe 3: Full-fidelity scenario snapshot — reproduceerbaarheid over jaren

### Beslissing

Elk scenario bevriest zijn volledige parameter-context en cascade-
definitie bij creatie. Herberekening gebruikt de gefrozen snapshot,
niet de live tabellen.

### Waarom

Payroll-scenarios worden gemaakt om beslissingen te nemen: salarisrondes,
budget-projecties, wat-als-analyses. Die beslissingen worden later
verantwoord — soms jaren later — aan bestuur, boekhouder, of
belastinginspecteur.

Reproduceerbaarheid is dan cruciaal: "wij besloten in Q2 2026 op basis
van deze berekening" moet in Q4 2028 nog steeds diezelfde berekening
opleveren.

Effective-dating alleen is onvoldoende. Als je een RSZ-tarief in juli
2026 aanpast met terugwerkende kracht (via `valid_from` in het verleden),
en je vraagt in oktober 2026 een oud scenario opnieuw op, dan krijg je
de gewijzigde tarief. De berekening klopt niet meer met wat toen was
gezien. Dit is geen theoretisch risico: RSZ-correcties met terugwerkende
kracht komen voor.

### Alternatieven overwogen

**Semantic-only snapshot, de POC-aanpak.**
`dim_scenario.param_snapshot_batch_id` verwijst naar een audit-log met
checksums en metadata, niet naar de werkelijke parameter-rijen. Je weet
WELKE batch geldig was, niet WAT er in stond. Onvoldoende voor
reproduceerbaarheid.

**Event-sourcing.** Elke wijziging aan populatie of scenario is een
event. Cascade herbouwt state door events te replayen. Perfect
reproduceerbaar, maar significant complexer dan snapshot-tabel. Voor
Belgische payroll waar wijzigingen laag-frequent zijn (paar per tenant
per maand) is event-sourcing overkill.

**Geen snapshot maar disclaimer.** Documenteer dat historische scenarios
mogelijk niet exact reproduceerbaar zijn. Werkt technisch, maar
accountants verwachten deze eigenschap van een payroll-tool.

### Trade-off

Storage per scenario is typisch enkele KB voor Belgische parameters. Bij
100.000 scenarios wordt dat honderden MB tot een GB. Op modern DB
verwaarloosbaar. Extra complexiteit in executor die snapshot-context
moet lezen ipv live tabellen.

Wat je terugkrijgt: volledige reproduceerbaarheid. Elk scenario blijft
draaien zoals het bij creatie draaide, ongeacht latere parameter-
wijzigingen. Belastinginspecteur die in 2028 vraagt "waarom deze mutatie
in juli 2026" krijgt exact het antwoord dat toen gegeven is.

Het randgeval dat aandacht vraagt: wat als cascade-formules zelf wijzigen
(nieuwe berekeningsmethode)? Twee opties: formule-code ook freezen in
snapshot (complex, versioning-risico) of formule-code git-based
versioneren en snapshot referenceert versienummer. Pragmatisch:
formules wijzigen zelden (grote wetsherziening), dus git-based met
gedocumenteerd beleid in DPO-documentatie is werkbaar. Voor een
volledig audit-proof setup zou formule-code ook expliciet moeten worden
gefrozen — dat is een grotere architectuur-beslissing die je bij eerste
formule-versie moet nemen.

### POC-bewijs

Migration `20260704000700_dim_scenario_snapshot_ref.sql` heeft
`param_snapshot_batch_id` als semantic-only reference. Comment in de
migration bevestigt: "POC-scope limitation: geen historische
reconstructie mogelijkheid". Voor productie is die limitatie niet
acceptabel.

Zie hoofdstuk 5 voor uitwerking (samen met data-model).

---

## Principe 4: Metrics-driven caching — geen cache tot bewezen behoefte

### Beslissing

Cache-tabellen, materialized data en query-caches worden pas gebouwd
wanneer metrics een concreet performance-probleem aantonen. Standaard:
cascade en analyses live draaien.

### Waarom

De POC introduceerde cache-strategie voordat er een performance-probleem
was. Voor 27 rijen was de cascade in milliseconden klaar. De mart-
tabellen waren pure kunst-om-de-kunst.

De echte kosten van premature caching bleken:

- 9 van 16 issues in de review-rondes waren cache-gerelateerd
- Cache-invalidatie werd de belangrijkste bron van bugs
- Debug-vragen verschoven van "waarom klopt deze berekening niet" naar
  "waarom is deze cache-rij stale"
- Concurrency-races (ISS-101) ontstonden puur door de cache-laag
- Triggers werden nodig, en die triggers gaven weer nieuwe bugs

Grofweg de helft van onze totale debug-tijd ging aan cache-hazards
zonder een performance-baat te leveren.

Bewuste principe-omkering ten opzichte van default-mindset: **niet
cachen tot metrics zeggen dat het moet**. Als p95 latency onder een
gewenste drempel blijft: geen cache. Als het pijn gaat doen: cache
waar het bewijs zegt, met invalidatie-strategie die bij de
mutation-patronen past.

### Alternatieven overwogen

**Cache-first voor toekomstige schaal.** Bouw cache-laag vanaf dag 1
zodat je klaar bent als je groeit. Klinkt vooruitziend maar is riskant:
cache-invalidatie-strategie hangt af van hoe users muteren, welke
queries dominant zijn, en waar bottlenecks zijn. Zonder metrics raad
je verkeerd — POC bewees dit met invalidation die UPDATE-events miste
en cross-tenant scope-fouten had.

**Redis vanaf dag 1 als externe cache-laag.** Vraagt je te weten welke
queries duur zijn zonder metrics. Vraagt bijkomende infrastructuur
(ander vendor, ander failure-mode). Verhoogt initiële complexiteit
zonder bewezen baat.

### Trade-off

Eerste user-flows zijn misschien langzamer. Cascade voor 100 contracten
duurt bijvoorbeeld iets langer dan een gecachte versie. Voor
POC-checkpoints en eerste tenants geen probleem. Voor grote schaal met
gelijktijdige calls: pijnpunt dat je dan met bewijs oplost, in plaats
van vooraf te gokken.

Wat je terugkrijgt: geen invalidatie-hell. Geen race-conditions tussen
refresh en mutation. Debugging is trivial ("data komt uit source").
Als cache-behoefte later komt, is die dan gerechtvaardigd door bewijs
en optimaal ingericht.

Het randgeval waar deze principe genuanceerd moet worden: loonkloof-
decompositie via Python-service is intrinsiek duur — 500 milliseconden
tot 2 seconden per tenant per kwartaal, op basis van POC-metingen. Hier
is cache waarschijnlijk vroeger gerechtvaardigd. Ook hier geldt: eerst
bouwen zonder cache, meten in productie, dan Redis-laag met TTL
toevoegen. Niet Postgres-materialized-data — dat is de cache-strategie
waarvan de POC bewees dat hij pijn geeft.

### POC-bewijs

Negen issues die grofweg de helft van onze debug-tijd hebben gekost:

- ISS-089: directe DML bypasste cache
- ISS-090: silent cache-failures
- ISS-091: cross-tenant scope in refresh
- ISS-092: cache-DELETE ná exception
- ISS-094: concurrent refresh race
- ISS-095: freshness contract voor param-updates
- ISS-100: UPDATE-trigger vergeten
- ISS-101: refresh-vs-mutation race
- ISS-102: data-loss bij multi-contract

Elke van deze issues zou niet bestaan hebben als we live hadden gedraaid.

Zie hoofdstuk 6 voor uitwerking.

---

## Principe 5: Feature flags vanaf commit één — progressive rollout als default

### Beslissing

Elke non-triviale feature (nieuwe pagina, nieuwe RPC, gewijzigde
berekening) zit vanaf de eerste commit achter een feature flag. Rollout
gaat via toenemende percentages of expliciete tenant-lijsten.

### Waarom

In de POC hebben we alles direct in main gemerged en gedeployed. Werkt
voor solo-development met externe AI-reviewers. Faalt zodra klanten in
productie hangen om drie redenen:

**Progressive rollout.** Nieuwe cascade-versie moet gradueel — een klein
deel van tenants proberen, dan uitbreiden, dan volledig. Zonder flags
kies je binair (alle tenants of niemand).

**Kill-switch.** Een buggy feature uitzetten moet in seconden kunnen,
niet in de tijd van een deploy. In een deploy-flow met tests en
migrations praat je over minuten. Voor productie is dat te lang.

**A/B experimenten en pilots.** Een subset van tenants (bijvoorbeeld
enterprise-klanten) een geavanceerde feature laten testen zonder
codebase te forken. Standaard-feature van feature-flag-tools.

Vanaf commit één is essentieel: als je later feature flags invoert
moet je bestaande features retrofit'en. Dat is refactor-werk. Als je
begint met flags, is elke feature automatisch onder discipline.

### Alternatieven overwogen

**Environment-based rollout.** Deploy nieuwe feature eerst naar staging,
internen testen, dan naar productie. Werkt maar is grover: geen A/B
binnen productie mogelijk, geen selectieve tenant-rollout.

**Feature-branches die lang leven.** Grote merge-hell risico. Andere
features op main worden geblokkeerd of gedwongen tot cherry-picks.
Praktisch onhoudbaar bij meerdere gelijktijdige feature-tracks.

Voor de flag-tooling zelf is er echte keuze tussen vendors. Vercel Edge
Config is gratis en dekt aan/uit + tenant-lijst + percentage rollout —
voldoende voor de meeste cases. PostHog en Statsig bieden meer (A/B
experimenten met significance-analyse, analytics-integratie) maar zijn
overkill voor pure aan/uit-flags. Bij begin: Vercel Edge Config; als
A/B-experimenten belangrijk worden: PostHog of Statsig erbij.

### Trade-off

Elke feature krijgt een guard-check. Discipline om oude flags op te
ruimen bij 100% rollout — anders ontstaat flag-drift waar niemand meer
begrijpt welke flag bij welke feature hoort.

Wat je terugkrijgt: progressive rollout mogelijk. Kill-switch voor bugs.
Sub-tenant-specifieke pilots. A/B-experimenten. Preview-per-PR met
flag-overrides voor testers.

### POC-bewijs

Toen we ISS-088 (kritieke security-blocker) vonden was de enige rollback-
optie `git revert` + nieuwe deploy. Met feature flag was het een toggle
van seconden.

Zie hoofdstuk 9 voor uitwerking (samen met testing en observability).

---

## Waarom juist deze vijf

Deze vijf principes hebben één ding gemeen: ze **elimineren categorieën
bugs** in plaats van individuele bugs. Elk van hen zou tenminste één
van onze 16 POC-issues hebben voorkomen. Sommige hadden er meerdere
voorkomen.

- RPC-only elimineert de categorie "verschillende security-mechanismen
  interacteren onvoorspelbaar"
- Declaratieve DAG elimineert de categorie "cascade-wijziging vereist
  code-refactor"
- Full-fidelity snapshot elimineert de categorie "historische scenario
  niet reproduceerbaar"
- Metrics-driven caching elimineert de categorie "premature-cache-
  invalidation-bug"
- Feature flags elimineert de categorie "productie-risico bij nieuwe
  feature"

Deze vijf zijn niet exhaustief. Er zijn andere architectuur-frameworks
die andere accenten leggen — Domain-Driven Design legt nadruk op
bounded contexts en ubiquitous language, hexagonal architecture op
poorten en adapters tussen domein en infrastructuur, event-sourcing op
onveranderbare event-streams als bron van waarheid. Deze frameworks
zijn niet in strijd met onze vijf principes maar leggen accenten die
we hier niet uitwerken.

De keuze voor juist deze vijf is empirisch: het zijn de patronen die,
in retrospect kijkend naar onze POC-issues, het meest pijn hebben
bespaard. Voor een ander domein of andere risico-profielen kunnen
andere principes belangrijker zijn.

## Verband met andere hoofdstukken

- Principe 1 (RPC-only) → hoofdstuk 4 uitgewerkt
- Principe 2 (declaratieve DAG) → hoofdstuk 3 uitgewerkt
- Principe 3 (snapshot) → hoofdstuk 5 uitgewerkt
- Principe 4 (metrics-driven caching) → hoofdstuk 6 uitgewerkt
- Principe 5 (feature flags) → hoofdstuk 9 uitgewerkt

Andere hoofdstukken behandelen beslissingen die niet in de vijf principes
vallen maar wel de architectuur vormgeven: tenant-model (2), frontend
(7), Python-service (8), startup-volgorde (10), operations en scale (11),
wanneer-niet (12).
