# Stratarius — Production Blueprint

Dit is een quick-start-guide voor het opzetten van de productie-versie van
Stratarius in een nieuwe repo. Gebaseerd op wat we in de POC hebben geleerd
(inclusief de 16 issues die we in twee reviews-rondes hebben opgeruimd).

## Voor wie

- Voor de dev(s) die de productie-versie gaan bouwen
- Voor de architect die de eerste week richting moet geven
- Voor Henk zelf om er over 3 maanden opnieuw naar te kijken

## Hoe deze guide te gebruiken

Lees de pagina's in volgorde als je aan het opstarten bent. Naar verwijzing:
elke pagina is standalone leesbaar, maar bouwt op de vorige voort.

**Elk hoofdstuk werkt beslissingen uit met dezelfde structuur:**
- **Beslissing** — wat we concreet kiezen
- **Waarom** — rationale
- **Alternatieven overwogen** — welke opties we hebben gewogen en waarom niet
- **Trade-off** — eerlijke kosten van deze keuze
- **POC-bewijs** — evidentie uit de POC waar relevant

De hoofdstukken bevatten geen implementatie-code. Het gaat om
beslissingen, niet copy-paste-snippets.

## Inhoud

1. [Fundamentele principes](./01-principes.md)
   De vijf beslissingen die alles anders maken. Lees dit eerst.

2. [Tenant + membership model](./02-tenant-model.md)
   Eigen model bouwen (basejump eruit). Schema, RLS-strategie, RPC-patroon.

3. [Cascade als declaratieve DAG](./03-cascade-dag.md)
   Config-driven executor voor de 9-stappen berekening. Fiscaal reviewbaar.

4. [Security model — RPC-only](./04-security-model.md)
   Een primair mechanisme, geen mix. REVOKE-strategie + audit-model.

5. [Data model](./05-data-model.md)
   Dim/fact/param structuur + denormalisatie + snapshot-model voor
   scenario-reproducibility.

6. [Caching strategie](./06-caching.md)
   Metrics-driven. Vier lagen. Wanneer wel, wanneer niet, wat NIET te doen.

7. [Frontend patterns](./07-frontend.md)
   Server-first met Next.js 16. Wanneer client-side. Waar Tanstack Query past.

8. [Python service architectuur](./08-python-service.md)
   Statistiek buiten Vercel Function. Deploy, retry, fallback.

9. [Testing, CI, observability](./09-testing-ops.md)
   pgTAP behouden. Playwright toevoegen. Sentry vanaf dag één. Feature flags.

10. [Startup-volgorde — modellen en principes vóór features](./10-startup-order.md)
    Elf lagen fundament. Welke modellen vóór welke andere. Waarom niet aan
    features beginnen tot alle lagen op orde zijn.

11. [Operations, schaal-fasering en blindspots](./11-operations-and-scale.md)
    Wat de eerste 10 hoofdstukken hebben laten liggen: billing, GDPR erasure,
    tenant lifecycle, backup, rate limiting, analytics, schaal-fasering per
    tenant-count.

12. [Wanneer NIET deze blueprint gebruiken](./12-when-not-to-use.md)
    Eerlijke zelf-test: wanneer is deze blueprint verkeerd voor jouw context?
    Zes contexten waar dit recept niet past. Zelftest en anti-recept.

## Één-pagina samenvatting

Als je alleen tijd hebt voor één pagina: lees
[fundamentele principes](./01-principes.md). Die 5 beslissingen zijn 80% van
het architecturele voordeel.

## Referentie naar POC

Verwijzingen naar `ISS-088` t/m `ISS-103` zijn issues uit de storybloq van
de huidige POC-repo (`.story/issues/`). Elke ISS heeft context over wat we
misten, hoe het opgelost is, en waarom die keuze anders had moeten zijn in
productie.

## Meta

Deze guide is bewust geen "software-architecture-in-15-minuten" — het is
een lessons-learned document uit een specifiek project. Als een keuze
tegenintuïtief lijkt, check het POC-bewijs waar ik naar verwijs.
