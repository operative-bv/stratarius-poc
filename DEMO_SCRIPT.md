# Stratarius POC — demo script

5-minuten flow om aan een prospect (HR-directeur, CFO, sociaal secretariaat) te laten zien wat het product doet en waar het naar toe gaat. Bedoeld voor iemand die de app moet demoen zonder eigen Stratarius kennis.

**Datum context**: juli 2026. Alle parameters zijn 2025-actueel + 2026 waar gepubliceerd.

---

## Voorbereiding (2 min voor het gesprek)

1. Log in op https://stratarius-poc.vercel.app met een testaccount
2. Zorg dat er een organisatie is met **geladen demo dataset** (1000 medewerkers). Zo niet:
   - Ga naar Data → Import
   - Klik "Laad demo dataset (1000 medewerkers)" — duurt ~1-2s
   - Wacht op de toast "1000 contracten geïmporteerd"
3. Test dat de populatie page laadt binnen 3s
4. Open dark mode als de prospect dat toont te waarderen

---

## De 5-min flow

### Moment 0 — De hook (10s)

> "In deze demo laat ik zien hoe je in Belgische context de volledige werkgeverskost berekent, wat if-scenarios doorrekent en loonkloof identificeert — allemaal met 2026-parameters en op een populatie van 1000 medewerkers."

**Klik**: startpagina van het dashboard.

Wijs op:
- **Headcount**: 1000 medewerkers
- **Bruto loonsom**: ~€3.5M / maand
- **Patronale kost**: ~€1.4M / maand (40% van bruto — belangrijk cijfer om te noemen)
- **Totale werkgeverskost**: ~€4.9M / maand → ~€59M jaarbasis

Loonkost trend chart toont seizoenpatroon met pieken vakantiegeld (mei/juni) + eindejaarspremie (december).

---

### Moment 1 — Populatie snapshot (60s)

**Navigatie**: Analyse → Populatie

> "Onder de motorkap draaien we voor elk contract de RSZ 9-stappen cascade — die is 100% data-driven vanuit de RSZ instructiegids. Op 2026-parameters."

Wijs op:
- **Filter**: Q2 2026, baseline scenario, alle teams
- **Tabel**: 1000 rijen met per contract:
  - Bruto → Basis RSZ (25% cat 1) → **Structurele vermindering** → Bijzondere bijdragen → Vakantiegeld → Extralegaal → Patronaal totaal → TCO
- **Weergave-toggle**: Maandkost / Jaarkost (×12) — laat rechts de jaar-projectie zien

**Klik door naar een specifieke contract-rij → Row detail sheet opent:**

> "Elke stap is uit te leggen tot op de wet — dit is niet een black-box maar een audit trail."

Wijs op:
- Stap 3 structurele vermindering: **γ-coëfficiënt 0.15** (aangepast in Q3 2025 regeerakkoord, POC pikt dat automatisch op via effective-dating)
- Bronnen bij elke stap (RSZ instructiegids URLs)

---

### Moment 2 — What-if scenario (60s)

**Navigatie**: Modellering → Scenarios

> "Een klant wilde weten: wat als we het salaris van het Sales team met 3% verhogen? Hier zetten we dat scenario in <30s op."

**Live actie**:
1. Loon-mutatie tab
2. Naam: "Sales +3%"
3. Baseline: current baseline scenario
4. Mutatie type: Percentage
5. Waarde: 3
6. Toepassen op: Alleen Sales team
7. Klik "Maak scenario → open in populatie"

Automatische redirect naar populatie in vergelijk-modus:

- **Δ Bruto**: +€X (positief oranje)
- **Δ Patronale kost**: **+€Y** — wijs op: "Patronale kost stijgt meer dan pro rata want structurele vermindering DAALT bij hoger loon"
- **Δ TCO**: +€Z

> "Dit is de daadwerkelijke impact — niet een schatting. Voor elke van de 200 Sales medewerkers is de cascade opnieuw doorgerekend met nieuwe parameters."

---

### Moment 3 — Ad-hoc simulator + effective-dating (45s)

**Navigatie**: Modellering → Simulator

> "Voor een specifieke case: één contract, één datum, ik verander alleen de periode."

**Live**: pas de periode aan van 2025-05-01 (Q2, γ=0.21) naar 2025-08-01 (Q3, γ=0.15).

Wijs op:
- Structurele vermindering VERANDERT tussen deze twee datums voor identieke input
- **Uitleg**: dat komt door de γ-shift in het regeerakkoord van juli 2025
- "Dit is één van de 8 fiscale wijzigingen die we in 2025-2026 automatisch oppikken"

Nog een dramatische shift laten zien: 2024 vs 2026 op een contract.

---

### Moment 4 — Loonkloof analyse (75s)

**Navigatie**: Analyse → Loonkloof

> "En dan het onderwerp waar iedere HR-directeur mee bezig is: pay gap. Belgische wet CAO 25 quinquies dwingt sinds 2023 loontransparantie af."

Wijs op:
- **Ruwe pay gap**: X% (mannen verdienen X% meer)
- **Kitagawa decompositie**:
  - Endowment (blauw): "verklaard door observables — functieniveau, ancienniteit, opleiding"
  - Residual (oranje): "onverklaard door de observables → mogelijk discriminatoir signaal"
- 95% CI half-width: interpretatie "is dit statistisch significant?"

**Klik "Run Oaxaca-Blinder"** (Python service):

> "Onder de motorkap is dit een echte OLS multivariate regressie in Python. Numpy + scipy voor de statistiek — statsmodels op prod past niet in Vercel's 250MB limiet dus we hebben het hand-gebouwd."

Wijs op de coefficient tabel:
- β mannen vs β vrouwen per variabele
- p-value: welke variabelen zijn statistisch significant
- "geen variatie in data" label bij `opl_laaggeschoold` (0 laaggeschoolden in demo)

---

### Moment 5 — Afsluiter (20s)

> "Wat je NIET zag in deze demo omdat we nog aan het bouwen zijn:
> - Historische data import via HR-systeem koppelingen (Workday, BambooHR, SD Worx eBlox, Attentia — roadmap Q3-Q4 2026)
> - Volledige multi-tenant met team management (basejump geïnstalleerd, RLS actief)
> - Automated compliance alerts (bijv. 'je pay gap overschrijdt CAO 25 threshold')
>
> Vragen?"

---

## Wat er WEL kan (om te noemen als geloofwaardigheidsanker)

- **RSZ basisbijdrage 25.00%** cat 1 (correcte tax-shift waarde, niet 25.07% benadering)
- **Structurele vermindering** — 4 opeenvolgende regimes:
  - 2024-Q1 t/m 2025-Q1: originele formule
  - 2025-Q2: geïndexeerde drempels (S0 → 11.233,89)
  - 2025-Q3+: γ verlaagd 0.21 → 0.15 (regeerakkoord)
  - 2026+: verdere herindexering (S0 → 11.458,57)
- **Plafond RSZ**: €85.000 (2025) → €86.700 (2026)
- **Wagen CO2 multiplier**: 2.75 (2025) → **4.0 (2026)** — grote wijziging
- **FSO klassiek**: 0.17% → 0.32% <20wn (2026)
- **Maaltijdcheque**: €6.91 → €8.91 (2026)
- **Vlaamse doelgroepvermindering ouderen**: afgeschaft per 2025-07-01
- Alle bronnen: RSZ instructiegids, VBO, SD Worx, Attentia, Securex, Partena, Acerta

## Wat NIET vertellen (nog)

- **POC_UNVERIFIED_2025 labels** — sommige cat 2/3 waarden zijn niet 100% geverifieerd. Voor pitch: framen als "we lopen door met een expert in productie".
- **Cross-tenant bug historie** — vandaag gefixt maar heeft geen plaats in pitch.
- **Cascade snelheid** — 1000 contracten = 2-4s wat kan opvallen. Als iemand vraagt: leg uit dat we een batch-RPC pattern hebben (stap 2 al af, andere stappen in roadmap).
- **Multi-entiteit tenants**: mismatch tussen KPI en decomp scope — geflagd als warning, maar issue nog niet volledig opgelost (RPC signature refactor).
- **Materialize cascade output**: nog niet — elke page-load = nieuwe compute. Roadmap.
- **pgTAP tests**: infrastructure staat, maar cross-tenant tests nog niet geschreven — vandaag ontdekten we een leak precies daar.

## Backup — als iets niet werkt

- **Populatie page traag**: leg uit dat cascade elke keer opnieuw rekent, roadmap = materialization
- **Oaxaca error**: mogelijk 0 laaggeschoolden in demo populatie → toon dat "dropped" label werkt correct
- **Login stuck**: hard refresh, dark mode toggle om te zien of theme provider draait
- **Demo dataset niet geladen**: gebruik "Laad demo dataset" knop (1-2s wacht)

## Herstel na demo — nette staat

Optioneel na de demo:
- Data → Import → "Wis populatie" knop (met AlertDialog confirmation)
- Handig als je meerdere prospects op één account demoet

## Referentiedata

Bronnen die je kan noemen als iemand vraagt "waar heb je die getallen vandaan":

- [RSZ Administratieve Instructies 2026/2](https://www.socialsecurity.be/employer/instructions/dmfa/nl/latest/instructions/socialsecuritycontributions/contributions.html)
- [Partena Structural Reduction 1 januari 2026](https://www.partena-professional.be/en/our-insights/infoflashes/nsso-structural-reduction-1-januari-2026)
- [Agoria Q3 2025 aanpassing structurele vermindering](https://www.agoria.be/nl/diensten/expertise/hr-legal-social-dialogue/aanwerven-tewerkstellen-ontslaan/sociale-zekerheid/rsz-bijdragen-verminderingen-en-formaliteiten/aanpassing-parameters-structurele-rsz-vermindering-vanaf-het-derde-kwartaal-2025)
- [Securex CO2 solidariteitsbijdrage 2026](https://www.securex.be/nl/lex4you/werkgever/nieuws/bedrijfswagen-de-solidariteitsbijdrage-voor-2026-is-gekend)
- [SD Worx Sociaal-juridische wijzigingen 2026](https://www.sdworx.be/nl-be/over-sd-worx/pers/2025-12-17-human-resources-wat-verandert-2026-op-sociaaljuridisch-vlak)
