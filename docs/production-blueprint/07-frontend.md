# 7. Frontend-architectuur

Next.js server-first met specifieke sub-beslissingen over waar client-
side interactivity nodig is en welke tooling daarbij past.

---

## Beslissing 1: Next.js App Router, server-first als default

### Beslissing

Frontend wordt gebouwd op Next.js 16 met App Router. Pages zijn Server
Components, data-fetching gebeurt server-side, mutaties via Server
Actions. Client Components alleen waar interactivity nodig is.

### Waarom

Server-first heeft drie concrete voordelen die in de POC-context
belangrijk zijn:

Data-fetching gebeurt in dezelfde omgeving als de RPC-boundary. Geen
network-roundtrip tussen browser en API — de Server Component roept
Supabase direct aan.

Initial page-load is HTML met data. Geen loading-state, geen "spinner
totdat React hydrateert". Voor accountants die pagina's op een dashboard
hebben openstaan is dit merkbaar sneller.

Type-safety loopt eind-tot-eind. Zelfde TypeScript-types voor DB (via
gen types), server code, en presentational rendering. Geen serialisatie-
grenzen die je met `as unknown as` moet oversteken.

### Alternatieven overwogen

**Traditional SPA (Remix in client-mode, of pure React SPA).** Werkt
maar vraagt aparte API-laag, aparte state-management, en meer code voor
loading-states.

**Server-rendered zonder React (Rails-style, Django).** Werkt goed voor
CRUD-apps maar interactivity binnen pagina's (bijvoorbeeld: simulator
met live-preview) wordt lastiger.

**Astro met React islands.** Sterk voor content-heavy sites. Voor app-
sites met dashboards en veel interactivity is Next.js beter passend.

### Trade-off

Server Components hebben een leercurve: welke code draait waar,
serialisatie tussen server en client, hydration-boundaries. Elk API-
call in een Server Component is een DB-call in dezelfde omgeving — dat
is een keuze die je bewust maakt.

Winst: minder client-side JavaScript, snellere initial load, betere
SEO, natuurlijke integratie met Supabase RPCs.

### POC-bewijs

POC gebruikte dit patroon met succes. 48 client components — bijna
allemaal shadcn/ui primitives. Data-fetching gebeurde overal server-side.
Werkte goed voor de use-cases.

---

## Beslissing 2: URL als bron van waarheid voor filter-state

### Beslissing

Filter-parameters (periode, scenario, team, view) leven in URL
`searchParams`. Server Component leest ze, rendert de bijhorende data.
Client-side updates gebeuren door navigatie naar nieuwe URL.

### Waarom

Deep-linkable: accountants delen URLs met collega's om precies dezelfde
view te tonen. Browser back-button werkt. Refresh behoudt state.
Bookmarks werken.

Deze eigenschappen zijn functioneel belangrijk voor accountants-workflow.

### Alternatieven overwogen

**Client-side state (React state, Zustand).** Werkt maar breekt
deep-linking. State gaat verloren bij refresh.

**LocalStorage of cookies voor filter-state.** Werkt maar is niet
deel-baar. En creëert ontkoppeling tussen wat de URL toont en wat de
gebruiker ziet.

### Trade-off

Elke filter-update triggert een navigatie en dus een server-round-trip.
Voor filters die snel veranderen (bijvoorbeeld typing in een zoekveld)
niet passend — daar wil je client-side state met debouncing.

Voor filter-formulier met submit-button (POC-patroon): perfect.

### POC-bewijs

POC's populatie-page en loonkloof-page gebruikten searchParams. Werkte
uitstekend voor de accountants-flow.

---

## Beslissing 3: Suspense boundaries voor progressive loading

### Beslissing

Zware data-fetches worden ge-wrapped in Suspense boundaries met
skeleton-fallbacks. Shell (filters, header) rendert direct; data streams
erna in.

### Waarom

Perceptual performance: gebruiker ziet meteen de shell, niet een blanke
pagina. Skeletons geven visueel verwachting welke data komt. Streaming
maakt subjectieve laadtijd korter zonder objectieve laadtijd te veranderen.

### Alternatieven overwogen

**Alle data wachten voor volledige render.** Simpelste code maar
gebruiker ziet blanke pagina tijdens fetch.

**Client-side loading-states.** Werkt maar vereist client component en
extra fetch-round-trip.

### Trade-off

Suspense-boundaries vragen zorgvuldig gebruik van React 18/19 features.
Skeleton-componenten moeten worden onderhouden (twee representaties
van "de tabel-structuur": echt en skeleton).

Winst: gebruikers ervaren de app als sneller.

### POC-bewijs

POC gebruikte Suspense-boundaries. Voor populatie-page werkte dit
uitstekend: filters direct beschikbaar, table streamt binnen.

---

## Beslissing 4: shadcn/ui behouden als component-library

### Beslissing

shadcn/ui blijft de UI-library. Componenten worden in `packages/ui`
gedeeld tussen apps. Domein-specifieke composites (KPICard,
MoneyDisplay, RSZBreakdown) worden erbovenop gebouwd.

### Waarom

shadcn/ui heeft in de POC bewezen productie-klaar te zijn. Composable,
customizable, geen versie-upgrade-treadmill (je copy't de code naar je
eigen repo).

Domein-specifieke composites erbovenop houdt UI consistent en herbruikbaar.

### Alternatieven overwogen

**Material UI, Ant Design, Chakra.** Werken maar zijn opinionated
qua styling. Customizen voor Belgische zakelijke esthetiek is meer werk
dan shadcn.

**Custom componenten from scratch.** Werk zonder eindpunt. Voor
middelgrote SaaS overbodig.

### Trade-off

shadcn-componenten leven in eigen repo, dus updates uit upstream moet
je expliciet ophalen. Discipline om je eigen customizations niet weg te
overwriten.

Winst: volledige controle, geen vendor-dependency, consistente
esthetiek.

### POC-bewijs

POC gebruikte shadcn. Werkte goed. Bugs die we vonden waren allemaal in
onze eigen composities, niet in shadcn-primitives.

---

## Beslissing 5: Tanstack Query alleen voor specifieke interacties

### Beslissing

Tanstack Query wordt geïntroduceerd als er een specifieke interactie is
die het rechtvaardigt. Voor standaard server-first flow niet nodig.

Concrete kandidaten voor Tanstack Query (op basis van huidige feature-
scope):

- Simulator met live cascade-preview bij typen
- Populatie-tabel met client-side sort/filter bij grote datasets
- Bulk-import progress via Realtime-subscription-bridge

### Waarom

Server Components + Server Actions dekken 80% van de flows zonder client-
side state-management. Tanstack Query is de juiste tool voor de resterende
20% waar client-side cache, optimistic UI, of real-time updates nodig
zijn.

### Alternatieven overwogen

**SWR.** Vergelijkbaar met Tanstack Query. Simpeler API, minder
features. Voor simple use-cases prima. Voor mutations met optimistic UI
en cache-invalidation is Tanstack Query rijker.

**Redux Toolkit Query.** Meer boilerplate. Passend als je al Redux
hebt.

**Geen data-fetching-library, native fetch + React state.** Werkt maar
je herbouwt caching-logica handmatig.

### Trade-off

Extra dependency om te leren en te onderhouden. Als er weinig
client-side data-fetching is, brengt het nauwelijks winst.

Winst voor de specifieke interacties: optimistic mutations, achtergrond-
refetch, cache-management uit de doos.

### POC-bewijs

POC had SWR geïnstalleerd maar gebruikte het alleen in één basejump-
hook. Dat is een teken dat de default (server-first) genoeg was.

---

## Beslissing 6: Client-state alleen waar nodig, Zustand voor global

### Beslissing

Client-side state alleen voor genuinely-client-side dingen: dark mode,
sidebar-collapse, active-modal. Voor global client-state (die niet in
URL past): Zustand.

Voor server-authoritative state: geen client-state, altijd server-
fetched.

### Waarom

Server-authoritative state die naar client wordt gemirrord is source of
bugs (drift, staleness). Beter: server-render met filter-in-URL,
mutation triggert revalidate.

Voor UI-only state (sidebar open/dicht): Zustand is minimaal en heeft
geen provider-nesting-overhead.

### Alternatieven overwogen

**Redux Toolkit.** Overkill voor UI-only state. Werkt goed als je al een
Redux-team hebt.

**React Context.** Werkt maar heeft re-render-implicaties bij grote
consumer-trees. Zustand is efficiënter.

**Recoil, Jotai.** Alternatieven met atom-based state. Werkt goed maar
Zustand is populair genoeg om als default te kiezen zonder controverse.

### Trade-off

Zustand-store moet worden opgezet en gestructureerd. Voor kleine apps
kan dit overkill zijn.

Winst: duidelijke scheiding tussen server-authoritative en UI-only
state.

### POC-bewijs

POC had geen dedicated client-state-library. Voor de POC-scope werkte
dat. Voor productie met complexer UI (bijvoorbeeld: draggable dashboard-
tegels) wordt Zustand snel nuttig.

---

## Verband met andere hoofdstukken

- Security model (hoofdstuk 4) definieert de RPC-boundary die Server
  Components aanroepen
- Testing (hoofdstuk 9) benadrukt Playwright golden paths voor de
  server-first flows, Vitest voor client-side utility functies
- Startup-volgorde (hoofdstuk 10) plaatst frontend in de latere lagen
  na fundament is gelegd
