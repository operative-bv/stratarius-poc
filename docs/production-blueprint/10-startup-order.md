# 10. Startup-volgorde — fundament vóór features

Volgorde-beslissing: welke architecturale lagen op zijn plaats zijn
voordat aan de eerste user-facing feature wordt begonnen.

---

## De hoofdbeslissing

### Beslissing

Elf architecturale lagen worden opgezet in specifieke volgorde vóór
de eerste domein-feature. Domein-features (populatie management,
simulator, loonkloof, exports) komen als laag 12 en later.

### Waarom

Elke feature die je bouwt maakt aannames over onderliggende structuur.
Als die structuur ontbreekt, wordt het inbouwen ervan later refactor-werk
in plaats van greenfield-werk.

Concrete voorbeelden uit ontbrekende foundation-lagen in de POC:

Zonder tenant-model op laag 5, wordt multi-tenant-aanname impliciet in
elke feature ingebakken. Retrofit vereist elke feature aan te passen
(ISS-098 patroon).

Zonder security-model op laag 6, wordt security-mechanisme per feature
ad-hoc gekozen. Emergent complexity is dan onvermijdelijk (ISS-089,
099, 100, 101).

Zonder CI-gates op laag 2, wordt bug-detectie afhankelijk van
handmatige reviews. Regressie-detectie wordt gaandeweg toegevoegd, na
de eerste incident.

Vanaf commit één de foundation opzetten is ~5% van totaal ontwikkel-
tijd voor middelgrote SaaS. Voorkomt refactor-tijd die vaak veelvoud
is.

### Alternatieven overwogen

**Feature-first, foundation reactief.** Bouw eerste feature, voeg
foundation toe wanneer nodig. Werkt in prototypes maar veroorzaakt
schulden in productie. Elke laag die later moet worden geretrofit is
duurder dan vooraf opzetten.

**Parallel-track: feature en foundation tegelijk.** Werkt in teams van
5+ met dedicated foundation-track. In solo of duo team wordt de
foundation-track altijd verwaarloosd voor "even deze feature".

**Iteratief: minimale foundation, dan feature, dan foundation
uitbreiden.** Werkt in principe maar vraagt frequente refactor. Voor
domain-heavy apps zoals payroll-cascade is de kern-foundation groot
genoeg dat iteratief bouwen inefficient wordt.

### Trade-off

Time-to-first-visible-feature is langer. Voor teams die snel demo's
willen kan dit als vertraging voelen.

Winst: elke feature bouwt op stabiele foundation. Refactor-cost
gaandeweg is minimaal. Compliance-, security-, en observability-eisen
zijn vanaf dag 1 gedekt.

### POC-bewijs

De POC bewees ontbreekende foundation-cost. 16 issues in reviews, ~5
weken werk aan cache-invalidatie voor 27 rijen, retrofit-werk voor
multi-membership en GDPR-audit. Als de foundation vóór features had
gestaan waren de meeste van deze issues categorisch niet ontstaan.

---

## De 11 lagen in volgorde

De volgorde is bewust: elke laag is prerequisite voor de laag erna.

### Laag 1: Repo-structuur en TypeScript-fundament

Monorepo (Turborepo), TypeScript strict mode, shared lint/format-config.
Eén package manager (pnpm) met workspaces. Elke logische unit is een
eigen package: `apps/web`, `packages/ui`, `packages/db-schema`,
`packages/domain`, `packages/config`.

**Waarom eerst:** alle andere lagen worden hierop gebouwd. Fout hier =
refactor overal.

### Laag 2: CI-pipeline met blocking gates

Blocking checks per PR: type-check, lint, build, pgTAP, Playwright,
Squawk. Branch-protection: main is protected, alle checks moeten groen.

**Waarom hier:** de discipline hardcoden vóór er features zijn. Als CI
later wordt toegevoegd, moet je bestaande code repareren om de checks
te halen.

### Laag 3: Supabase project, environments, migration workflow

Supabase Pro project in EU-region. Environments: preview (per PR),
staging (main branch), production (release-tagged, manual approval).
Type-generatie script.

**Waarom hier:** database is de bron van waarheid. Zonder proper
environment-scheiding wordt dev en prod snel verweven.

### Laag 4: Auth en business-user-model

Supabase Auth voor authenticatie, `public.users` tabel voor business-
user-data, trigger die sync. Session-context helper.

**Waarom hier:** alles wat volgt (tenant-model, security) leunt op user-
identity.

### Laag 5: Tenant en membership-model

Zie [hoofdstuk 2](./02-tenant-model.md). Tenants, memberships (N:M
met role), invitations. Multi-membership first-class.

**Waarom hier:** tenant-model is prerequisite voor security-model
(dat op tenant-check leunt) en voor URL-routing (per-tenant slug).

### Laag 6: Security-model (RPC-only surface)

Zie [hoofdstuk 4](./04-security-model.md). REVOKE alle direct grants,
alle domein-access via SECURITY DEFINER RPCs met p_tenant_id en
audit-log.

**Waarom hier:** security-model bepaalt hoe elke feature met data
communiceert. Als features vóór security worden gebouwd, hebben ze
eigen ad-hoc security-patterns die conflict opleveren.

### Laag 7: Observability en feature flags

Sentry vanaf commit één. PostHog voor analytics en feature flags. Elk
Server Action en API-route gewrapped.

**Waarom hier:** wanneer je begint met domein-features, wil je meteen
weten of ze breken en of ze gebruikt worden. Als monitoring later
wordt toegevoegd, mis je de eerste weken data.

### Laag 8: Effective-dating pattern demonstreren

Zie [hoofdstuk 5](./05-data-model.md). Bouw één parameter-tabel
(bijvoorbeeld param_rsz) met valid_from/valid_to. Documenteer pattern.

**Waarom hier:** het pattern moet vast staan vóór alle domain-tabellen
gebouwd worden. Anders krijg je inconsistente temporele modellering.

### Laag 9: Cascade DAG-schema en executor

Zie [hoofdstuk 3](./03-cascade-dag.md). Bouw
`cascade_step_definition`-tabel en generieke executor met dummy
formule-functies. Test met minimaal voorbeeld.

**Waarom hier:** cascade-executor is de kern van het domein. Als je
formule-functies bouwt zonder executor, weet je niet of de executor-
architectuur werkt.

### Laag 10: Scenario snapshot-model

Zie [hoofdstuk 5](./05-data-model.md). Bouw `scenarios` en
`scenario_snapshots` tabellen. Implementeer `create_scenario_with_snapshot`
RPC. Test dat snapshot correct wordt gefreezed.

**Waarom hier:** snapshot-model moet vast staan vóór er scenarios in
productie worden aangemaakt. Retrofitten van snapshot op bestaande
scenarios is complex.

### Laag 11: Golden path E2E-test

Playwright test die de complete onboarding-flow dekt: signup → tenant
setup → dashboard.

**Waarom hier:** bewijst dat lagen 1-10 samenwerken. Als deze test niet
groen krijgt zonder productcode, is er iets fundamenteel mis.

---

## Vanaf laag 12: features

Populatie management, simulator, scenarios, loonkloof, exports, billing.
Elk volgt de regels die in lagen 1-11 zijn vastgelegd:

- Achter een feature flag
- Met pgTAP-test voor DB-gedrag
- Met Playwright golden path als user-facing
- Via SECURITY DEFINER RPC met p_tenant_id + audit
- Effective-dated waar temporeel

Deze regels lijken restrictief maar besparen de refactor-schulden die
we in de POC hebben opgeruimd.

---

## Wanneer deze volgorde flexibel maken

De volgorde is niet dogmatisch. Twee scenarios waarin flexibiliteit
gerechtvaardigd is:

Als je een specifieke technische onzekerheid hebt (bijvoorbeeld:
"kan Python-service dit type berekening in acceptabele tijd?"), is
een spike naar die vraag nuttig vóór foundation-af is. Beperk de spike
tot informatie-vergaring, gooi de code weg, bouw dan weer volgens
foundation-volgorde.

Als er externe deadlines zijn (klant-demo, VC-pitch), kan een MVP-tak
naast de foundation-tak worden gebouwd. Dat is bewuste dubbel-werk
schuld die je later moet opruimen. Documenteer expliciet welke
schulden je neemt.

---

## POC-bewijs

Onze POC bouwde features vóór foundation. De meeste van onze 16 issues
zijn direct gevolg:

- Multi-membership niet first-class (ISS-098): omdat tenant-model laat
  werd geformaliseerd
- Vier security-mechanismen door elkaar (ISS-089/099/100/101): omdat
  security-model niet vooraf was gedefinieerd
- Cache-hazards (9 issues): omdat cache-strategie ad-hoc werd bedacht
- Geen CI (kwaliteit werd handmatig bewaakt): omdat CI-setup werd
  uitgesteld

De blueprint-volgorde neemt deze pijn weg door foundation vooraf te
formaliseren.

---

## Verband met andere hoofdstukken

- Elke laag heeft een dedicated hoofdstuk dat de beslissingen uitwerkt
- Wanneer-niet (hoofdstuk 12) noemt contexten waarin deze foundation-
  first-benadering niet passend is
- Operations (hoofdstuk 11) neemt over vanaf laag 12, wanneer features
  in productie draaien
