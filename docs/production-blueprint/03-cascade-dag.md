# 3. Cascade als declaratieve DAG

Uitwerking van principe 2 uit hoofdstuk 1. De cascade-berekening wordt
niet meer een call-chain van functies maar een data-driven graph die
door een generieke executor wordt uitgevoerd.

---

## Beslissing 1: Cascade-definitie als configuratie-data

### Beslissing

Elke stap van de cascade wordt beschreven in een tabel
`cascade_step_definition` met velden voor execution order, input-refs,
output-key, formule-referentie, non-cumulatie-relaties en effective-dating.

### Waarom

Cascade-wijzigingen zijn frequent genoeg dat code-changes voor elke
wijziging onwerkbaar zijn: RSZ-tarieven jaarlijks, doelgroepverminderingen
bij regeerakkoorden, sector-CAO's per PC-code. Bij data-driven cascade
wordt een wijziging een INSERT in configuratie-tabel — reviewable door
een fiscaal-jurist, deploybaar zonder code-migratie.

Effective-dating op de cascade zelf betekent dat oude scenarios blijven
werken met hun eigen cascade-versie, en nieuwe scenarios de nieuwe
regels toepassen. Kan niet in code-based cascade zonder complexe
versioning-infrastructuur.

### Alternatieven overwogen

**Rules engine als externe service (Drools, Camunda DMN).** Krachtig
maar vraagt aparte deployment en runtime. Voor ~30 cascade-regels die
we hebben is dat over-tooling. Rules engines lonen wanneer je duizenden
regels over verschillende domeinen hebt.

**Cascade in TypeScript.** Verplaatst berekening naar application-layer.
Verliest atomicity met data (de cascade en de fact-data leven niet meer
in dezelfde transactie) en verplaatst je audit-log-bron. Verlaat de
POC-keuze om cascade in Postgres te houden — die keuze was juist een
van de goede POC-beslissingen.

**Behouden call-chain (POC-aanpak).** Werkt maar mist reviewbaarheid en
deploybaarheid-zonder-code.

### Trade-off

Meer upfront ontwerp om de configuratie-schema en executor te bouwen.
Als je later wilt afwijken van het uniforme formula-signature (bijv.
een stap die extra parameters wil), moet je de executor uitbreiden of
een generieker input-mechanisme kiezen.

Wat je terugkrijgt: cascade-wijziging zonder code-deploy. Reviewbaarheid
door niet-technische stakeholders. Effective-dating als natuurlijk
gevolg van de tabel-structuur.

### POC-bewijs

15 cascade-migraties met compositie-logica verspreid over
`cascade_populatie_snapshot`, `cascade_stap4_non_cumulatie` en drie
"integration"-migraties. Elke cascade-wijziging tijdens de POC was een
nieuwe migration. Voor productie waar cascade-wijzigingen kwartaal-cyclus
zijn: onhoudbaar.

---

## Beslissing 2: Executor met dynamic SQL, gedisciplineerd

### Beslissing

Één generieke executor-functie leest de cascade-definitie en roept per
stap de bijhorende formule-functie aan via `EXECUTE format(...)` met
`%I` (identifier quoting) voor de functie-naam. Formule-namen worden
via whitelist gevalideerd.

### Waarom

De aard van declaratieve cascade vereist dynamic dispatch: welke functie
wordt aangeroepen hangt af van de configuratie-data. Twee manieren om
dat te bereiken: (a) dynamic SQL met `EXECUTE`, (b) een grote CASE-WHEN
in de executor die alle bekende formules statisch dispatched.

Optie (a) is flexibeler (nieuwe formule toevoegen = twee inserts: één
in whitelist, één in cascade_step_definition, plus de formule-functie
zelf). Optie (b) vereist bij elke nieuwe formule een executor-migration.

Optie (a) is gekozen, met discipline om de SQL-injection-risico's te
mitigeren.

### Alternatieven overwogen

**Grote statische CASE-WHEN.** Veilig tegen SQL-injection maar vraagt
migration bij elke nieuwe formule. Neemt een deel van het declaratieve
voordeel weg.

**Executor in application-layer.** TypeScript executor die per stap de
juiste RPC aanroept. Levert dispatch-flexibiliteit zonder dynamic SQL,
maar herintroduceert het probleem dat cascade en data niet in dezelfde
transactie leven.

### Trade-off

Dynamic SQL is een SQL-injection-oppervlak als niet correct beschermd.
Non-negotiable discipline:

- Formule-functie-namen worden ge-quote met `%I` (identifier), nooit `%s`
- Cascade-configuratie is REVOKED voor authenticated — alleen platform-
  admin kan definities wijzigen
- Whitelist-tabel beperkt welke functie-namen überhaupt aanroepbaar zijn
- Whitelist wordt via CHECK-constraint en trigger afgedwongen

Als één van deze disciplines wegvalt, is de declaratieve architectuur
juist gevaarlijker dan een call-chain zou zijn geweest. Dit is een
serieus punt om in code-review discipline op te houden.

### POC-bewijs

Geen POC-precedent voor dit patroon. De risico's zijn afgeleid van
algemene SQL-injection-security-analyses in de context van dynamic SQL
in PL/pgSQL.

---

## Beslissing 3: Condition-regels als structured JSON, geen embedded SQL

### Beslissing

Conditionele stappen (bijvoorbeeld "alleen toepassen als
werkgeverscategorie = 1") worden gedefinieerd als JSON-rules die door
een eigen mini-evaluator worden geïnterpreteerd. Geen embedded SQL-
expressions in de cascade-definitie.

### Waarom

Een JSON-rule zoals `{"and": [{"eq": ["cat", 1]}, {"gt": ["age", 30]}]}`
is beperkter dan willekeurige SQL, maar dekt de business-logica die
Belgische payroll nodig heeft (equality, comparisons, AND/OR/NOT).

Voordeel: kan geen SQL-injection zijn. Er wordt nooit tekst naar
`EXECUTE` gegeven; alleen jsonb-data-manipulatie.

### Alternatieven overwogen

**Embedded SQL-expressions.** Krachtigst maar creëert weer een SQL-
injection-surface als de cascade-configuratie ooit door tenant-users
bewerkt zou kunnen worden. Ook onbedoeld: platform-admin die een typo
maakt zou de executor kunnen kapotmaken.

**Externe DSL / expression-taal.** Geef gebruikers een mini-taal om
condities uit te drukken. Krachtig maar we bouwen dan een programmeertaal
voor onszelf. Overkill voor Belgische payroll-condities die zich in
enkele operatoren laten uitdrukken.

### Trade-off

Beperkter uitdrukkings-vermogen dan willekeurige SQL. Als je in de
toekomst complexer conditie-logica nodig hebt (bijvoorbeeld: aanroep
van een aangepaste business-functie), moet je de evaluator uitbreiden.

Grote winst in veiligheid: geen SQL-injection-oppervlak in de
condition-check.

### POC-bewijs

Geen POC-precedent — de POC had cascade als call-chain zonder expliciete
condities. In productie-context is dit een belangrijke security-
beslissing die vaak wordt overgeslagen.

---

## Beslissing 4: Trace-log per cascade-uitvoering

### Beslissing

Elke cascade-uitvoering produceert een trace-record met per-stap:
step_id, input, output, of geskipped (met reden), en welke formule is
aangeroepen. Trace wordt opgeslagen in een aparte tabel.

### Waarom

Payroll-berekeningen worden verantwoord aan bestuur, accountant,
belastinginspecteur. Vraag: "waarom is stap 4 nul voor dit contract?"
Antwoord met trace: "stap 4 is geskipped wegens mutual_exclusion_with
stap 3 die output leverde".

Zonder trace moet je de cascade-code mentaal simuleren om de vraag te
beantwoorden. Met trace is het één query.

Ook voor debugging: als je een berekening ziet die ongeloofwaardig is,
trace laat zien welke inputs elke stap kreeg en welke output produceerde.
Fout isoleren wordt trivial.

### Alternatieven overwogen

**Geen trace, on-demand recompute voor debugging.** Bespaart storage.
Faalt voor scenarios waar de historische parameter-context relevant is
(zie snapshot-model, hoofdstuk 5). Ook: reproducible traces vragen
snapshot-context, wat weer complexer wordt zonder gepersisteerde trace.

**Alleen samengevatte log-line per run.** "Cascade voor contract X, output
totale kost 3200 EUR". Werkt voor high-level auditing maar biedt geen
antwoord op "waarom".

### Trade-off

Storage per trace: klein per stuk, maar bij miljoenen cascade-runs kan
het optellen. Aanbeveling: trace bewaren voor scenarios waar audit
relevant is (bijvoorbeeld: opgeslagen scenarios). Voor eenmalige
preview-berekeningen kan trace optioneel worden.

Wat je terugkrijgt: audit-transparantie, debugging-precisie,
verantwoording-mogelijkheid.

### POC-bewijs

POC had geen trace-log. Wanneer we een cascade-uitkomst wilden
verklaren, moesten we de code manueel doorlopen. Voor de POC-omvang
haalbaar, voor productie waar accountants "waarom"-vragen stellen niet
schaalbaar.

---

## Beslissing 5: Formule-functies met uniforme signature

### Beslissing

Alle `calc_*` functies hebben dezelfde signature: `(input jsonb, periode
date) → numeric`. De executor bouwt de input-jsonb uit de accumulator
volgens de cascade-step-definition's input_refs.

### Waarom

Uniforme signature is noodzakelijk voor de generieke executor. Zonder
uniformiteit zou de executor per stap moeten weten welke argumenten die
functie verwacht, wat de configuratie-tabel weer complexer maakt.

Jsonb als input is flexibel: kan één numeriek veld bevatten of een
complete context met contract-details. Nieuwe input-behoeften vragen
geen signature-wijziging.

### Alternatieven overwogen

**Per-formule specifieke signature met dispatch-tabel.** Elke formule
declareert eigen args. Executor kijkt op welke args nodig zijn en bouwt
call. Meer werk in de executor-logica; geen echte winst.

**Formule-functies die de accumulator direct raken.** Formule leest en
schrijft naar volledige accumulator. Krachtiger maar breekt de
encapsulatie: één formule kan andere formules' output overschrijven.

### Trade-off

Uniforme signature betekent dat formule-code een beetje moet worden om
jsonb-parsing te doen. In PL/pgSQL is dat kleine boilerplate maar
consistent.

### POC-bewijs

POC-formules waren losse RPCs met verschillende signatures. Werkte voor
directe aanroepen vanuit `cascade_populatie_snapshot`. Werkt niet voor
een generieke executor zonder harmonisatie.

---

## Waarom de dispatch-veiligheid zo veel aandacht krijgt

Twee van de vijf beslissingen (2 en 3) gaan primair over security-
disciplines rondom dynamic SQL. Dat is bewust.

De cascade-DAG-aanpak is een architectuur-keuze met een specifieke
klasse risico's: als de dispatch-mechaniek gecompromitteerd raakt
(SQL-injection via formule-naam, of via condition-expression) is de
impact groot omdat de executor `SECURITY DEFINER` draait en dus
Postgres-owner-rechten heeft.

Bij de call-chain-aanpak van de POC waren deze risico's er niet omdat
alle functie-namen statisch waren. De declaratieve aanpak wint aan
reviewbaarheid en flexibiliteit maar verliest die impliciete
security-eigenschap. Als team is discipline vereist om deze veiligheid
te herstellen.

Dit is een goed voorbeeld van hoe architectuur-keuzes trade-offs
introduceren die je in gedachten moet houden. De keuze is verdedigbaar,
maar niet gratis.

---

## Verband met andere hoofdstukken

- Snapshot-model (hoofdstuk 5) verzekert dat cascade-uitvoeringen
  reproduceerbaar zijn: snapshot bevriest ook de cascade-definitie
- Security-model (hoofdstuk 4) legt de RPC-boundary vast waarbinnen de
  executor draait
- Testing (hoofdstuk 9) benut de uniforme formule-signature voor
  unit-testing per formule
