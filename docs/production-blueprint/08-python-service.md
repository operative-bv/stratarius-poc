# 8. Python-service architectuur

De statistische berekeningen (Oaxaca-Blinder decompositie) leven in een
Python-service. In de POC was dat een Vercel Function; voor productie
schuift dat naar een dedicated compute-omgeving.

---

## Beslissing 1: Statistische berekeningen in Python, niet in Postgres of TypeScript

### Beslissing

Statistische decomposities (OLS-regressie, Oaxaca-Blinder, en toekomstige
methoden zoals quantile regression of bootstrap CIs) leven in een
Python-service. Postgres roept via HTTP aan als het cascade-resultaat
input is; anders roept de app-server aan.

### Waarom

Python heeft de rijkste statistische libraries (numpy, scipy, statsmodels,
scikit-learn). Voor academisch-onderbouwde methodes zoals Oaxaca-Blinder
zijn deze libraries de canonieke referentie.

Alternatieven zijn niet passend:

PL/pgSQL kan geen OLS-regressie doen zonder eigen matrix-algebra te
implementeren. Waar POC dat had gedaan voor eenvoud, is dat niet
schaalbaar naar meerdere methodes.

TypeScript heeft `simple-statistics` en `mathjs`, maar de statistische
bibliotheek is dun en minder mature. Voor accountants-verantwoording
wil je de canonieke tools.

### Alternatieven overwogen

**Alles in Postgres met eigen matrix-algebra.** Werkte in POC voor
Oaxaca omdat we het handmatig implementeerden. Voor uitbreiding met
nieuwe methoden is dat niet houdbaar.

**Alles in TypeScript.** Nog minder mature statistische ecosysteem.
Debug-tools zijn niet gericht op statistiek.

**Rust met linfa.** Krachtig en snel. Voor deze schaal onnodig
complex. Rust-ecosysteem in dit domein minder mature dan Python.

### Trade-off

Extra dienst betekent extra inter-service communicatie (HTTP-boundary),
extra deployment, extra failure-mode. Vraagt monitoring en fallback.

Winst: volledige statistische ecosystem voor accountants-verantwoording.
Nieuwe methodes zijn een `pip install` verwijderd.

### POC-bewijs

POC's `api/oaxaca.py` deed OLS handmatig met numpy omdat statsmodels +
pandas de 250MB Vercel-bundle-limiet overschreden. Voor Oaxaca met één
methode werkte dit. Bij uitbreiding wordt dit maintenance-schuld.

---

## Beslissing 2: Dedicated Python-compute, niet Vercel Python Function

### Beslissing

De Python-service draait op een dedicated compute-omgeving (Modal, Fly.io
of AWS Lambda met numpy-layer), niet op Vercel Python Functions zoals in
POC.

### Waarom

Vercel Python Functions hebben significante beperkingen die POC bewees:

- 10 seconden timeout (60 op Pro plan). Voor tenants met 5000+ personen
  is dat te kort.
- 250 MB bundle-limit. Statsmodels + pandas past niet — we moesten
  handmatig numpy-code schrijven.
- Cold-start van ~500ms per aanroep.
- Geen persistent memory of connection-pooling.

Dedicated compute (Modal, Fly, Lambda) heeft langere timeouts, geen
bundle-limits, en betere resource-scaling.

### Alternatieven overwogen

**Modal.** Python-focused serverless. Support voor 5-minuten (sync) en
15-minuten (async) timeouts, unlimited pip-packages, EU-region beschikbaar,
pay-per-second billing. Vaak passendste voor statistische workloads.

**Fly.io met eigen Docker.** Persistent Python HTTP-server. Geen cold-
start, meer controle over deployment. Vraagt Docker-expertise en meer
DevOps-werk.

**AWS Lambda met numpy-layer.** Werkt goed maar meer AWS-ecosysteem-
werk. Als er al AWS-infrastructuur is: makkelijker; anders extra vendor.

**Vercel Python behouden.** Werkt voor kleine batches (<100 personen).
Als schaal-cap.

Hybride benadering: Vercel Python voor snelle kleine batches, Modal/Fly
voor grote batches. Extra complexiteit in routing (welke aanroep gaat
waar); waarschijnlijk niet waard tot bewezen bottleneck.

### Trade-off

Extra vendor of deployment-target om te beheren. Meer configuratie-werk
initieel.

Winst: geen artificial limits op berekening. Statistische toolbox is
volledig beschikbaar.

### POC-bewijs

POC's Vercel Python werkte voor demo-context met 27 personen. Bij eerste
productie-tenant met 500+ personen zou dit een probleem worden.

---

## Beslissing 3: HMAC-signed inter-service communicatie

### Beslissing

Node → Python communicatie is HTTP met HMAC-SHA256 signed body via een
gedeelde secret. Timestamp in header voor replay-protection.

### Waarom

De Python-service en Node-app leven in verschillende deployment-omgevingen.
Zonder authenticatie kan iedereen die de URL vindt de Python-service
aanroepen. Dat is een cost-risk (Python-calls zijn duur) en een security-
risk (statistische decomposities van andere tenants triggeren).

HMAC met shared secret is de simpelste correctness-gedreven oplossing.
Timestamp voorkomt replay-attacks binnen een klein window.

### Alternatieven overwogen

**mTLS tussen services.** Strikter, meer setup. Voor twee-service-scenario
overkill.

**JWT met kort-lopende tokens.** Werkt maar vraagt JWT-signing service.
HMAC is simpeler.

**IP-whitelisting.** Werkt in cloud-omgevingen maar minder betrouwbaar
bij scaling of vendor-switches. HMAC is agnostisch.

### Trade-off

Gedeeld secret moet geroteerd worden bij bepaalde events (dev-lek,
routing-wijziging). Beheerslast klein maar niet nul.

Winst: bulletproof authenticatie tussen services zonder JWT-infrastructuur.

### POC-bewijs

POC gebruikte dit patroon. Werkte goed. Behouden.

---

## Beslissing 4: Fallback naar simpeler SQL-model bij Python-uitval

### Beslissing

Wanneer de Python-service niet bereikbaar of gefaald is, valt de app
terug op een simpler Kitagawa-decompositie die volledig in SQL kan.
User ziet een banner dat het gereduceerde model actief is.

### Waarom

Statistische decompositie is complex; volledige Python-uitval mag niet
betekenen dat de loonkloof-page onbruikbaar wordt.

Kitagawa-decompositie is beperkter dan Oaxaca-Blinder (geen coefficient-
effect isolatie) maar levert bruikbare raw-gap-cijfers. Voor accountants
die het "even willen zien" is dat voldoende.

Fallback wordt duidelijk gemarkeerd in UI: dit is niet het volwaardige
model, Python-service was niet beschikbaar.

### Alternatieven overwogen

**Geen fallback, error-pagina bij Python-uitval.** Werkt maar
beschikbaarheid van loonkloof-analyse wordt volledig afhankelijk van
Python-service uptime. Voor accountants die op deze data leunen niet
acceptable.

**Fallback naar cached-oude-resultaten.** Werkt maar toont mogelijk
inconsistente data (nieuwe contracten, oude berekening). Gereduceerd
model actueel is bruikbaarder.

### Trade-off

SQL-based Kitagawa implementeren en onderhouden is extra werk. Niet
gebruikt in happy-path.

Winst: platform blijft functioneel bij statistiek-service-uitval.
Vertrouwen van accountants dat "de tool blijft werken".

### POC-bewijs

POC had geen fallback. Als Vercel Python down was, was loonkloof-page
kapot. Voor demo prima; voor productie niet.

---

## Beslissing 5: Async processing voor grote batches

### Beslissing

Bij tenants met > 1000 personen wordt de Oaxaca-berekening asynchroon.
Frontend geeft "wordt berekend, we sturen je email zodra klaar" ipv
wachten op een blocking HTTP-call.

### Waarom

Sync HTTP-call heeft een praktisch timeout (30 sec voor most stacks).
Grote batches kunnen langer duren. Async ontkoppelt user-wachten van
berekening-duur.

Modal en Fly ondersteunen async met durable execution: als de worker
crash't midden in de berekening, wordt hij herstart.

### Alternatieven overwogen

**Alles sync, met langere timeouts.** Werkt tot batch-size-cap. Bij
enterprise-klanten met 10.000+ personen alsnog fail.

**Trigger.dev of Inngest voor async-orchestratie.** Krachtig maar
extra tool. Voor eenvoudige "berekening → notify" flow overkill.

### Trade-off

Async-flow vraagt UI-work: "berekening in progress" state, notificatie-
mechanisme (email of realtime), history-log.

Winst: schaal zonder timeout-plafond.

### POC-bewijs

POC was volledig sync omdat batches klein waren. Bij eerste enterprise-
tenant met grote populatie is dit een blocker.

---

## Verband met andere hoofdstukken

- Caching (hoofdstuk 6) wijst loonkloof-decompositie aan als eerste
  cache-kandidaat wegens hoge computation-cost
- Testing (hoofdstuk 9) benoemt Python-service-fault-injection als
  onderdeel van golden-path E2E-tests
- Operations (hoofdstuk 11) werkt async-processing en rate limiting
  verder uit
