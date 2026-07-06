# 9. Testing, CI en observability

Wat we uit de POC behouden (pgTAP), wat we toevoegen (Playwright, Sentry,
feature flags), en waarom.

---

## Beslissing 1: pgTAP-suite behouden en uitbreiden

### Beslissing

De POC's pgTAP-suite (57 files, 843 assertions) wordt behouden en
uitgebreid. Elke nieuwe RPC of belangrijke schema-wijziging krijgt een
pgTAP-test. Suite draait in CI op elke PR.

### Waarom

pgTAP tests dingen die unit tests niet dekken: RLS-gedrag, permissions,
cascade-correctness, cross-tenant-isolation. Deze zaken zijn juist waar
POC-bugs zaten.

Concreet uit onze POC: ISS-088 (scenario RPC zonder tenant-check) werd
gevonden door Codex-review en vervolgens regression-locked in pgTAP.
Zonder pgTAP zou een toekomstige refactor dit opnieuw kunnen breken
zonder detectie.

### Alternatieven overwogen

**Alleen unit tests + integration tests op de app-laag.** Werkt maar
mist DB-gedrag. Voor apps met complexe RLS is dit onvoldoende.

**Integration tests via de HTTP-API.** Kunnen RLS testen door
authenticated calls te doen. Trager dan pgTAP, en vaak minder precies.
Complementair, niet vervangend.

### Trade-off

Elke feature met DB-impact krijgt een pgTAP-test. Discipline om dit
consistent te doen.

Winst: bugs in security-boundary, cascade-correctness, en constraint-
validatie worden vroeg gevangen.

### POC-bewijs

843 assertions in POC. Vingen dingen zoals cross-tenant leak (ISS-077,
test 65), scenario-tenant-check (ISS-088, test 61), en multi-membership
isolation (ISS-103, test 66). Zonder pgTAP-suite waren deze bugs post-
deploy ontdekt.

---

## Beslissing 2: Playwright golden paths, geen exhaustieve E2E

### Beslissing

Playwright dekt 5-8 golden path user journeys (login, tenant setup,
import, view populatie, create scenario, view loonkloof). Niet elke
edge case.

### Waarom

E2E-tests zijn duur om te schrijven en onderhouden. Golden paths hebben
de hoogste waarde per euro: als login of scenario-creatie stuk gaat is
de app onbruikbaar. Edge cases worden goedkoper gedekt door pgTAP +
unit tests.

De regel is: elke journey die essentieel is voor een accountant om
waarde te halen uit de app krijgt een golden path test.

### Alternatieven overwogen

**Exhaustieve E2E-suite.** Volledig gedekt maar hoge maintenance-load.
Slow feedback in CI. Voor middelgrote SaaS overkill.

**Alleen visual regression tests (Percy, Chromatic).** Vangt UI-regressie
maar niet functionele bugs. Complementair, niet vervangend.

**Geen E2E, alleen unit + integration.** Werkt tot een production-bug
in de user-flow. Deploy-vertrouwen wordt aangetast.

### Trade-off

E2E-tests draaien traag (~30 sec voor 5 tests met setup). Vergroot de
CI-tijd. Flaky tests moeten worden onderhouden.

Winst: high-confidence dat de golden paths werken bij elke PR.

### POC-bewijs

POC had geen E2E-tests. Bugs zoals de clear-populatie-signature-mismatch
(die pas via user-test werd ontdekt) waren met golden path E2E gevangen.

---

## Beslissing 3: Sentry vanaf commit één

### Beslissing

Sentry-integratie voor error tracking, performance monitoring en session
replays wordt opgezet vanaf de eerste commit. Client + server + edge
configs.

### Waarom

Bugs in productie ontdek je door monitoring, niet door user-complaints.
Zonder Sentry ontdek je een bug pas als een gebruiker het meldt — dan
is de impact al gemaakt.

Session replays zijn extra waardevol: bij een reproductie-mysterie kun
je exact zien wat de gebruiker deed.

Voor payroll-app met accountants die precisie eisen: verwachting is dat
bugs snel worden gedetecteerd en gefixt.

### Alternatieven overwogen

**Alleen server-logs (Vercel Logs).** Werkt technisch maar vangt geen
client-side errors. En vraagt zelf reactief zoeken ipv proactief
alerting.

**Alternatieven: Bugsnag, Rollbar, Datadog APM.** Vergelijkbaar met
Sentry. Sentry heeft breedste Node/Next/React-integratie en decent
free tier.

**Custom error-logging naar eigen Postgres.** Werkt maar bouwt tooling
die vendors gratis geven. Geen alerting, geen dashboards.

### Trade-off

Sentry vraagt PII-masking discipline (in de POC-context: geboortedatum,
geslacht, andere PII mag niet in session replays terechtkomen).
Configuratie-werk om dit correct te doen.

Winst: real-time zichtbaarheid op productie-issues. Alerting bij spikes.

### POC-bewijs

POC had geen error tracking. Bugs werden ontdekt via user-tests of via
Codex-review. Voor productie is dat te laat.

---

## Beslissing 4: CI met blocking gates

### Beslissing

Elke PR moet groen zijn op alle checks vóór merge is toegestaan.
Blocking jobs zijn: type-check, lint, build, pgTAP-suite, Playwright
golden paths, en migration safety (Squawk).

### Waarom

Als CI-checks niet blocking zijn, worden ze theater. Ontwikkelaars
mergen "we fixen het later" en later komt zelden.

Blocking dwingt de discipline dat main altijd deployable is.

### Alternatieven overwogen

**Non-blocking checks (informational only).** Werkt in teams met sterke
review-discipline. In solo-context of AI-assisted-context onvoldoende.

**Alleen sommige checks blocking.** Bijvoorbeeld: type-check blocking,
pgTAP informational. Werkt maar verlies je de garantie dat pgTAP-
regressie wordt gedetecteerd.

### Trade-off

Broken CI kan een PR blokkeren op iets dat niet-triviaal is (bijvoorbeeld
flaky Playwright test). Vraagt discipline om flaky tests te fixen ipv
skipsen.

Winst: hoge kwaliteit-garantie in main. Deploy-vertrouwen.

### POC-bewijs

POC had geen CI. pgTAP werd handmatig lokaal gedraaid. Gevolg: bugs die
pgTAP had kunnen vangen werden pas ontdekt in reviews of user-tests.

---

## Beslissing 5: Squawk voor migration safety in CI

### Beslissing

Squawk (migration linter) draait op elke gewijzigde migration in een PR.
Onveilige DDL (zoals `alter table drop column` op grote tabellen zonder
statement-timeout) blokkeert merge.

### Waarom

Migrations kunnen bij deploy productiedatabase blokkeren. Ontwikkelaars
weten niet altijd welke DDL onveilig is bij grote datasets. Squawk
codificeert deze kennis.

### Alternatieven overwogen

**Handmatige review van migrations.** Werkt in seniorteams maar mist
regressie. Squawk als extra vangnet.

**Migration-review via specialist DBA.** Voor teams zonder senior DBA
onbereikbaar. Squawk vervangt basis-check.

### Trade-off

Squawk-regels kunnen soms te streng zijn (bijvoorbeeld: waarschuwing
voor CREATE INDEX zonder CONCURRENTLY, wat voor kleine tabellen niet
nodig is). Configuratie om project-specifieke overrides te maken.

Winst: unsafe migrations worden vroeg gedetecteerd.

### POC-bewijs

POC had een lesson uit ervaring: "nooit edit-in-place op gepushte
migrations". Squawk formaliseert deze en soortgelijke regels.

---

## Beslissing 6: PostHog voor product-analytics en feature flags

### Beslissing

PostHog wordt gebruikt voor product-analytics (welke features worden
gebruikt, waar haken users af) en feature flag management.

Alternatief: Vercel Edge Config voor pure aan/uit-flags plus Sentry
performance data. Werkt maar mist product-analytics.

### Waarom

Feature-adoption en drop-off zijn belangrijke data om product-beslissingen
te nemen. Zonder analytics bouw je op onderbuikgevoel.

PostHog integreert flags en analytics in één tool. Bij gebruik van
alleen Vercel Edge Config voor flags moet je analytics elders halen.

### Alternatieven overwogen

**Statsig.** Vergelijkbaar met PostHog. Sterker in A/B experiment
analysis met significance testing. Zwakker in autocapture. Voor teams
die veel A/B'en: Statsig; voor teams die vooral analytics + flags
willen: PostHog.

**Amplitude of Mixpanel + Vercel Edge Config.** Amplitude is
industry-standard voor product-analytics. Duurder tier vaak nodig voor
kleine teams. PostHog free tier is genereus.

**Google Analytics.** Voor B2B SaaS met privacy-scherpte niet ideaal.
GDPR-integratie complex.

### Trade-off

Extra vendor (PostHog) met eigen dashboard om te leren en configureren.
PII-masking discipline voor session replays.

Winst: product-decisions op basis van data, feature flag management
inclusief graduele rollout.

### POC-bewijs

POC had geen analytics. Voor demo-context prima. Voor productie waar
je wilt weten "welke tenants gebruiken de simulator" essentieel.

---

## Verband met andere hoofdstukken

- Security-model (hoofdstuk 4) beschrijft de audit-log die naast Sentry
  voor security-events zorgt
- Startup-volgorde (hoofdstuk 10) plaatst deze tooling in de eerste
  lagen — foundation before features
- Operations (hoofdstuk 11) werkt out-of-band alerting en on-call
  rotatie verder uit
