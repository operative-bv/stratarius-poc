# 12. Wanneer NIET deze blueprint gebruiken

De blueprint is opinionated productie-architectuur voor middelgrote B2B
SaaS in complex financieel domein. Er zijn contexten waar dit specifieke
recept niet passend is. Dit hoofdstuk is expliciet over die contexten.

---

## De impliciete aannames van de blueprint

Voordat we naar contexten kijken, expliciet welke aannames de blueprint
maakt:

- Er is tijd om foundation vóór features op te bouwen (grofweg enkele
  weken tot maanden)
- Het team snapt (of leert) Postgres-heavy patterns: PL/pgSQL, RLS,
  effective-dating
- Het domein is Belgische payroll of vergelijkbaar: complex,
  gestructureerd, met stabiele wetgeving
- Compliance-eisen zijn materieel (GDPR, fiscale audit)
- Verwachte schaal zit in het 10-500-tenant-bereik (fase 1-2 in hoofdstuk 11)
- Solo of duo development, mogelijk met AI-assistentie

Als drie of meer van deze aannames niet kloppen bij jouw context, is de
blueprint waarschijnlijk niet de juiste keuze.

---

## Context 1: Product-market-fit-onzekerheid

### Situatie

Er zijn nog geen betalende klanten. Product-hypothese is niet gevalideerd.
Deadline om te bewijzen is weken, niet maanden.

### Waarom deze blueprint niet passend is

De blueprint vraagt significante foundation-investering vóór eerste demo.
In een PMF-context is die investering een gok: je bouwt architectuur
voor een product dat mogelijk niet doorgaat.

Refactor-cost is beperkt bij kleine schaal. Als je later ontdekt dat je
architectuur moet omgooien: je hebt geen tenant-legacy die het duur
maakt.

### Wat wel te doen

Blijf op de POC-architectuur, marginaal verbeterd:

- Voeg CI toe (relatief goedkoop)
- Voeg Sentry toe (uren-werk)
- Voeg feature flags toe (dagen-werk)
- Fix bekende POC-bugs

Ga demo's doen. Krijg pilot-klanten. Valideer of product-hypothese
klopt.

### Wanneer alsnog naar blueprint bewegen

- Eerste betalende klant tekent contract
- Multi-membership use-case bewijst zich
- Compliance-vraag komt van jurist of eerste enterprise-klant

---

## Context 2: Team zonder Postgres-heavy background

### Situatie

Dev-team komt van React/Prisma/Vercel-stack. PL/pgSQL is nieuw. RLS is
een puzzel. Effective-dating begrijpen ze niet.

### Waarom deze blueprint niet passend is

De blueprint vraagt discipline die vaardigheid vereist. RPC-only surface
is een patroon dat je moet leren. Cascade als data-driven graph in
Postgres is niet mainstream. Advisory locks, security_invoker views,
en snapshot-model zijn allemaal expertise-gebieden.

Onboarding van een nieuwe dev in deze architectuur is grofweg een
paar maanden. Voor een klein team met tijdsdruk kan dat te lang zijn.

### Wat wel te doen

Kies boring architecture over clever architecture:

- Cascade in TypeScript (niet PL/pgSQL) met heldere unit-tests
- Prisma of Drizzle voor DB-comfort
- Auth via Clerk of WorkOS (zero-config, geen tenant-model zelf)
- Enterprise features via managed services (Auth0-audit, OneTrust voor
  compliance)

Trade-off: je bouwt sneller, hebt meer vendor-cost, minder controle
over performance. Voor 90% van B2B SaaS is dat de juiste keuze.

### Wanneer alsnog naar blueprint bewegen

- Postgres wordt bottleneck en er is geen andere optie
- Compliance-vraag die vendor niet dekt
- Team heeft senior DB-engineer geworven

---

## Context 3: Ander domein dan gestructureerde financiële cascades

### Situatie

Je bouwt geen Belgische payroll, maar bijvoorbeeld:

- Real-time trading (sub-100ms latency-eis)
- IoT streaming data (miljoenen events per seconde)
- Content-heavy CRUD (blog, e-commerce catalog)
- Chat/messaging (WebSocket-heavy)

### Waarom deze blueprint niet passend is

De blueprint is geoptimaliseerd voor "complex domain-logic op Postgres
met compliance-focus". Voor bovenstaande domeinen is Postgres met
SECURITY DEFINER RPCs niet de juiste optimalisatie.

Real-time trading vraagt gespecialiseerde stack (Cloudflare Workers,
edge KV). IoT streaming vraagt time-series-DB (TimescaleDB, ClickHouse).
Content vraagt CMS (Sanity, Payload). Chat vraagt Socket.io + Redis.

### Wat wel te doen

Kies architectuur die past bij het domein. Blueprint-principes zoals
"één security-model" en "feature flags vanaf dag 1" zijn domain-
onafhankelijk en blijven relevant. Concrete implementaties niet.

---

## Context 4: Enterprise-eisen buiten wat blueprint dekt

### Situatie

Eerste klant is Big-4 of vergelijkbaar met eisen die de blueprint niet
dekt:

- SAML SSO + SCIM provisioning
- On-premise deployment (klant-VPC)
- ISO 27001 certificatie binnen 12 maanden
- Formele risico-assessment per feature

### Waarom deze blueprint tekortschiet

Supabase Auth doet SAML in Pro maar SCIM alleen in Enterprise.
On-premise is niet Supabase-natief. ISO 27001 vraagt processen die de
blueprint alleen aanraakt.

### Wat wel te doen

Blueprint-principes blijven relevant. Implementatie-stack verandert:

- WorkOS voor SAML + SCIM + directory sync
- Vervang Supabase voor self-managed Postgres of enterprise-DB-vendor
- Consultant voor ISO 27001 traject
- Deploy op klant-VPC via Kubernetes

Bij enterprise-eerste-klant is dit vaak eerste architectuur-omslag.
Verwacht additionele weken foundation-werk.

---

## Context 5: Regulatory of compliance-eisen buiten GDPR

### Situatie

Belgische toezichthouder (FSMA, KSZ, of vergelijkbaar) heeft specifieke
technische eisen:

- Data-residency in België verplicht (niet EU-breed)
- Audit-log signed door externe Trusted Service Provider
- Formele risico-assessment per feature-rollout

### Waarom deze blueprint tekortschiet

EU-region ≠ België-only. Sentry-hashes zijn geen TSP-signature. Feature-
flag rollout heeft geen approval-gate met risico-assessment.

### Wat wel te doen

Blueprint-principes blijven relevant. Deployment-stack en compliance-
processen anders:

- Belgische managed hosting (Combell, Escapenet, of eigen data-center)
- Externe TSP-integratie voor audit-signing
- Compliance-officer als approval-gate in CI (manual review vóór
  feature-flag naar 100%)
- Documented change-management-proces

Consultatie van compliance-jurist bij architectuur-fase essentieel.

---

## Context 6: Andere schaal dan de blueprint aanneemt

### Situatie

Extreem klein (minder dan 10 tenants gepland ooit) of extreem groot
(duizenden tenants direct nodig).

### Waarom deze blueprint niet passend is

Voor extreem klein: foundation-investering is niet gerechtvaardigd. Een
paar Excel-macros of een basis-CRUD-app is efficienter.

Voor extreem groot vanaf start: fase 3 architectuur nodig direct, niet
fase 1. Partitioning, sharding, dedicated BI-infra moeten vanaf dag 1.
De blueprint's geleidelijke opbouw past niet.

### Wat wel te doen

Voor extreem klein: overweeg of een SaaS-app überhaupt de juiste
oplossing is. Misschien is een script of een Google-Sheets-integratie
efficienter.

Voor extreem groot: consulteer een senior architect. De blueprint als
startpunt is te licht.

---

## Zelftest

Beantwoord eerlijk:

1. Heb ik weken tot maanden vóór eerste betalende klant om foundation te
   bouwen? Ja → blueprint past; Nee → context 1 of 4.

2. Snapt mijn team Postgres, RLS, PL/pgSQL, effective-dating? Ja → past;
   Deels → onboarding-plan (context 2); Nee → boring stack.

3. Is complexe gestructureerde domein-logic (payroll, tax, insurance) mijn
   domein? Ja → past; Nee → context 3.

4. Groei ik naar 10-500 tenants in jaar 1-2? Ja → past; Groter → fase 3
   uit hoofdstuk 11; Kleiner → context 1 of 6.

5. Heb ik GDPR + fiscale compliance als eisen? Ja → past; Meer (enterprise,
   sector-specifiek) → context 4 of 5.

6. Ben ik solo, duo, of klein team? Ja → past — één architect kan de
   principes bewaken; Team van 20+ → aanvullende architecture-review-
   forums en RFC-proces nodig.

Als drie of meer nee zijn: de blueprint is waarschijnlijk niet de juiste
match. Gebruik de principes uit hoofdstuk 1 als richting, negeer de
concrete implementaties.

---

## De rode draad

Blueprint is opinionated productie-architectuur voor middelgrote B2B
SaaS in complex financieel domein met stabiele wetgeving. Weeg voor
jouw context:

- Domein-complexiteit (payroll = complex, blog = eenvoudig)
- Compliance-materialiteit (GDPR + fiscaal = zwaar, publieke SaaS =
  licht)
- Team-capabilities (senior DB = ja, Prisma-team = nee)
- Runway + time-to-market (tijd voor foundation = ja, weken deadline =
  nee)
- Verwachte schaal (10-500 tenants = sweet spot)

Als drie of meer niet passen: pak alleen de principes uit hoofdstuk 1
en negeer de rest. De principes zijn domein-onafhankelijk; de
implementaties zijn context-specifiek.

---

## Anti-recept — universeel toepasbaar

Ongeacht context zijn deze anti-patronen altijd fout, gebaseerd op
lessons uit de POC:

- Mixed security-modellen zonder discipline welke wanneer
- Cache voor performance-probleem dat er niet is
- Triggers voor domain-logic (alleen voor pure audit)
- Snapshot-only-semantic zonder data-freezing
- CI zonder blocking gates (dan is CI theater)
- Vertrouwen op één reviewer (of één AI) voor architectuur-beslissingen

Deze zes zijn altijd fout. De rest is context-afhankelijk.
