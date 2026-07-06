# 11. Operations, schaal en blindspots

Beslissingen die de eerste 10 hoofdstukken bewust hebben laten liggen:
schaal-fasering, billing, GDPR erasure, tenant lifecycle, disaster
recovery, rate limiting details, analytics/BI-toegang.

---

## Beslissing 1: Schaal-fasering — één blueprint past niet één-op-één voor alle schaal

### Beslissing

De blueprint werkt niet uniform voor tenants van 10 tot 5000. Drie
fases met verschillende architectuur-nadruk:

- Fase 1: eerste tenants (grofweg tot enkele tientallen). Foundation
  van blueprint, geen mart-caches, geen partitioning, Vercel Python
  is voldoende.
- Fase 2: schaling operations (tientallen tot honderden tenants).
  Redis-caching voor dure queries, read-replica overwegen, Python-
  service naar dedicated compute.
- Fase 3: distributed operations (honderden en meer). Partitioning
  van fact-tabellen, dedicated BI-infrastructuur, multi-region-
  deployment overwegen.

De exacte grenzen tussen fases hangen af van usage-patronen. Metrics
zeggen wanneer een fase overgaat, niet vooraf gekozen tenant-count.

### Waarom

Fase 1 architectuur voor fase 3 werkt niet: te complex voor de schaal.
Fase 3 architectuur voor fase 1 werkt evenmin: overkill die vertraging
oplevert zonder baten.

De grens tussen fases is empirisch. Als p95 latency onder acceptable
blijft en errors uitblijven: je zit nog in fase 1. Als queries traag
worden en database-load stijgt: fase 2 kondigt zich aan.

### Alternatieven overwogen

**Eén-size-fits-all architectuur.** Klinkt eenvoudig maar past niet.
Kleinere klanten betalen voor complexiteit die ze niet nodig hebben;
grotere klanten worden geblokkeerd door architectuur die niet schaalt.

**Duidelijke tenant-count-grenzen (bijv. "onder 50 = fase 1").** Klinkt
scherp maar is arbitrair. Beter: metrics-gedreven overgang.

### Trade-off

Vraagt monitoring om te weten waar je bent. Als monitoring ontbreekt,
kun je niet weten of je fase-overgang mist.

Winst: proportionele investering in architectuur. Geen premature
scaling.

---

## Beslissing 2: Billing via Stripe, subscription-model met usage-based dimensie

### Beslissing

Subscriptions in Stripe, mirror in eigen `subscriptions` tabel. Plans:
trial, starter, pro, enterprise. Feature-gating per plan afgehandeld in
`packages/domain/plan-features.ts`. Usage-metrics (aantal contracten,
Oaxaca-runs) worden gemeten voor eventuele usage-based billing later.

### Waarom

Stripe is defacto voor SaaS-billing. Alternatieven (Paddle, LemonSqueezy)
werken maar hebben minder complete ecosystem.

Feature-gating in code (niet in database) houdt plan-definitie zichtbaar
en versionbaar in git.

Usage-metrics voorzien op mogelijk later toe te voegen usage-based
billing zonder retrofit-werk.

### Alternatieven overwogen

**Paddle als merchant of record.** Handelt VAT/BTW af. Voor SaaS in EU
met Belgische klanten aantrekkelijk. Nadeel: transactiekosten hoger.

**Custom invoicing zonder platform.** Werkt in enterprise-context waar
klanten liever custom contracten hebben. Voor middelgrote SaaS te
handmatig.

**Chargebee, Recurly.** Recurring-billing platforms bovenop Stripe.
Toevoegen tot een derde partij die je ecosystem beheert.

### Trade-off

Stripe-integratie is werk (webhooks, subscriptions, invoices, retry-flow
bij failed payments). Discipline om webhook-events atomair te verwerken.

Winst: gestandaardiseerde billing zonder eigen platform te bouwen. VAT/
BTW-support via Stripe Tax add-on. Card + SEPA + bank transfer support.

---

## Beslissing 3: GDPR erasure via anonymisatie + audit-behoud

### Beslissing

Bij "vergeet mij"-verzoek: persoonsgegevens (naam, geboortedatum,
national number) worden geanonymiseerd. Contracten en fact-data blijven
bestaan met geanonymised person-reference (voor aggregate statistiek).
Audit-log blijft 7 jaar bewaard (Belgische fiscale eis) inclusief de
erasure-actie zelf.

### Waarom

Belgische en EU-brede regelgeving: individu heeft recht op vergetelheid.
Payroll-app moet dit ondersteunen.

Belgische fiscale wet vereist 7 jaar audit-bewaring. Deze twee eisen
zijn schijnbaar conflict maar zijn oplosbaar: anonymiseer PII, behoud
audit-log van acties.

Retention-policy documenteren is verplicht voor DPO. Zonder document =
juridische boete-risico.

### Alternatieven overwogen

**Volledige hard delete inclusief audit.** Botsen met fiscale
bewaarplicht. Niet acceptabel.

**Alleen soft-delete zonder anonymisatie.** Werkt technisch maar PII is
nog aanwezig. Erasure-recht is niet vervuld.

### Trade-off

Anonymisatie-logica is complex omdat je moet weten welke velden PII
zijn en welke afgeleide data ook moet worden anonymised. Bijkomend:
statistische bruikbaarheid van geanonymised data moet worden gevalideerd
(re-identification-attacks).

Winst: compliant, met behoud van fiscale bewaring.

### POC-bewijs

POC had geen erasure-workflow. Voor demo-context prima. Voor productie
met echte persoonsgegevens verplicht.

---

## Beslissing 4: Tenant lifecycle expliciet gemodelleerd

### Beslissing

Tenant heeft state-machine: trial → active → past_due → canceled →
soft_deleted → hard_deleted. Overgangen zijn voorspelbaar met retention-
windows tussen: 30 dagen past_due tot canceled, 90 dagen canceled tot
soft_deleted, 30 dagen soft_deleted tot hard_deleted.

### Waarom

Zonder expliciete state-machine wordt tenant-lifecycle ad-hoc. Data-
export op churn wordt vergeten. Recovery-window bij per-ongeluk cancel
niet gedefinieerd.

Retention-windows geven users tijd om terug te komen (past_due),
data te exporteren (canceled), en accountants om te compileren voor
volgende jaar (soft_deleted).

### Alternatieven overwogen

**Binaire actief/inactief.** Werkt maar mist grace-periods. Klant die
één maand niet betaalt verliest permanent access.

**Manuele lifecycle-management.** Werkt bij weinig tenants. Bij grotere
schaal onhaalbaar.

### Trade-off

State-machine-logica in code. Discipline om overgangen automatisch te
maken (billing-webhook triggert overgang, cron drops hard_deleted).

Winst: voorspelbaar tenant-gedrag. Data-export als recht bij churn.

---

## Beslissing 5: Backup en disaster recovery met expliciete RPO/RTO

### Beslissing

Supabase Point-in-Time-Recovery (7 dagen op Pro plan) plus weekly
offsite-backup naar S3. RPO/RTO-targets worden gedefinieerd:

- RPO (maximum acceptabel data-verlies): binnen 1 uur, via PITR
- RTO (time to recover): binnen 4 uur, via PITR of S3-restore

Recovery-runbook wordt gedocumenteerd en getest via kwartaal-oefening.

### Waarom

Zonder expliciete targets zijn RPO/RTO-vragen "wat is acceptabel?" niet
te beantwoorden. Met targets kun je architectuur-keuzes verantwoorden
(bijvoorbeeld: weekly S3-backup is voldoende omdat PITR de dagelijkse
window dekt).

Getest runbook is de enige die betrouwbaar is. Ongeteste plannen falen
altijd.

### Alternatieven overwogen

**Alleen Supabase PITR zonder externe backup.** Werkt tot Supabase
zelf een incident heeft. Externe backup is verzekering.

**Real-time cross-region replication.** Krachtig maar duur en complex.
Voor eerste productie-fase overkill; voor fase 3 overwegen.

**Backup naar Belgische managed storage.** Voor extra data-residency-
scherpte. Voor GDPR is EU-region van S3 doorgaans voldoende; als
Belgische data-residency verplicht wordt: overweeg Combell of Escapenet.

### Trade-off

Testen van DR-runbook is werk dat "nooit nodig" lijkt tot het nodig is.
Discipline om kwartaal-tests te doen ondanks andere prioriteiten.

Winst: bewezen recovery-capability. Vertrouwen bij enterprise-klanten
(essentieel voor Big-4-verkoop).

---

## Beslissing 6: Rate limiting op meerdere lagen, getallen op basis van monitoring

### Beslissing

Rate limiting op drie lagen: edge (Vercel/Cloudflare), middleware (per-
user via Redis), en per-tenant in dure RPCs. Concrete limits worden
op basis van productie-monitoring vastgesteld. Initiële defaults zijn
geïnformeerd raden.

### Waarom

Zie [hoofdstuk 4 beslissing 5](./04-security-model.md#beslissing-5-rate-limiting-op-meerdere-lagen).

Reden om getallen niet vooraf te fixen: zonder productie-usage weet je
niet welke limits te strak zijn (blokkeren legitiem verkeer) of te ruim
(niet effectief tegen abuse). Beter: begin met defaults, monitor, pas
aan.

### Alternatieven overwogen

Zie hoofdstuk 4.

### Trade-off

Zie hoofdstuk 4.

### POC-bewijs

POC had geen rate limiting. Voor demo-context niet nodig. Bij eerste
productie-tenant kan één misconfigured integratie een Python-budget
opeten.

---

## Beslissing 7: Analytics/BI via dedicated read-only role, niet direct schema-access

### Beslissing

Voor BI-tools of eind-user data-exports: dedicated `analytics_read` role
in Postgres met SELECT-only rechten. RLS-policy filtert per gebonden
tenant. Voor grotere BI-behoefte in fase 2/3: read-replica plus
Metabase-achtige tool.

### Waarom

Direct authenticated-role toegang tot rauwe schema doorbreekt de RPC-
only-security. BI-users hebben andere behoeften (aggregate queries,
cross-table joins) die niet passen bij domain-RPCs.

Dedicated role met read-only rechten en RLS-scoping is compromis:
BI-tools kunnen queryen zonder auditing-overhead, maar tenant-scope
blijft afgedwongen.

### Alternatieven overwogen

**Alle exports via RPC.** Werkt voor eenvoudige exports. Voor complexe
BI-analyses vraagt dit aparte RPCs per query-type — snel onhoudbaar.

**CDC-streaming naar warehouse (BigQuery, ClickHouse).** Sterk voor
grotere schaal. In fase 3 overwegen.

**Direct Postgres access voor accountants.** Werkt maar geen tenant-
scope. Niet acceptabel voor GDPR.

### Trade-off

Dedicated role en RLS-policy vragen configuratie. Rate-limiting op
BI-queries (die vaak zwaar zijn) apart in te richten.

Winst: BI-behoeften zonder security-boundary breken.

---

## Beslissing 8: Audit-log-management via pg_partman

### Beslissing

`audit_log` en andere time-series-tabellen worden gepartitioneerd op
maand-granulariteit via pg_partman. Retention-beleid: actieve partitions
laatste 24 maanden in Postgres, ouder naar S3 in Parquet-formaat, na 7
jaar verwijderd (behoudens legal hold).

### Waarom

Zie [hoofdstuk 5 beslissing 5](./05-data-model.md#beslissing-5-time-series-data-audit-trace-partition-door-tijd).

Concrete retention-getallen zijn Belgisch-fiscaal gemotiveerd (7 jaar
bewaarplicht) en operationeel praktisch (24 maanden actief houdt
queries snel).

### Alternatieven overwogen

Zie hoofdstuk 5.

### Trade-off

Zie hoofdstuk 5.

---

## Meta: dit hoofdstuk is niet exhaustief

Deze acht beslissingen dekken de meest voorkomende blindspots uit de
eerste 10 hoofdstukken. Andere onderwerpen die aandacht vragen bij
verdere schaling maar hier niet zijn uitgewerkt:

- Multi-region compliance en data-residency-details (SCC's, DPA-
  templates)
- Sub-processor management en ISO 27001-audit-voorbereiding
- On-call rotatie en incident-response-runbooks
- Chaos engineering en resilience-testing
- Formule-versionering voor cascade (kort geraakt in hoofdstuk 1
  principe 3)

Bij elke van deze onderwerpen: consultatie van specialist (privacy-
jurist, compliance-consultant, SRE-specialist) is bij productie-fase
verstandig. Wat dit hoofdstuk geeft is de checklist "wat je moet
dekken", niet de volledige uitwerking.

---

## Verband met andere hoofdstukken

- Data model (hoofdstuk 5) levert de tabel-structuren voor billing,
  audit, en retention
- Security model (hoofdstuk 4) geldt ook voor billing en analytics
- Startup-volgorde (hoofdstuk 10) neemt over vanaf laag 12; dit
  hoofdstuk dekt operationele beslissingen die vanaf laag 12 relevant
  worden
