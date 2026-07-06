# 6. Caching-strategie

Uitwerking van principe 4 uit hoofdstuk 1. Cache pas na bewezen behoefte,
in vier lagen prioritized van eenvoudig naar complex.

---

## Beslissing 1: Metrics-first, geen cache-laag vooraf

### Beslissing

Bij aanvang van de nieuwe repo worden geen mart-tabellen, materialized
views of Redis-caches gebouwd. Cascade en analyses draaien live. Cache
wordt toegevoegd wanneer metrics een concreet performance-probleem
laten zien.

### Waarom

Zie principe 4 uit hoofdstuk 1. De POC bewees dat cache-first-mindset
bugs oplevert die geen performance-baat compenseren.

### Alternatieven overwogen

Zie hoofdstuk 1 principe 4 voor het volledige alternatieven-overzicht
(cache-first voor toekomstige schaal, Redis vanaf dag 1).

### Trade-off

Zie hoofdstuk 1 principe 4.

### POC-bewijs

9 cache-gerelateerde issues in de reviews (ISS-089 t/m ISS-102 selectie),
zonder aantoonbare performance-winst.

---

## Beslissing 2: Vier cache-lagen, prioritized

### Beslissing

Wanneer cache nodig blijkt, wordt gekozen uit vier lagen in volgorde van
eenvoud:

1. HTTP-cache headers via Vercel Edge (voor stateless of tenant-scoped
   stateless data)
2. Next.js `unstable_cache` met tags (in-request memoization)
3. Redis via Upstash (voor dure cross-request results met TTL)
4. Postgres materialized data (alleen bij bewezen bottleneck, met
   versioning-based cache-keys)

Laag 1 is de default; hogere lagen worden pas overwogen als lagere
lagen niet voldoen.

### Waarom

Elke laag heeft eigen operationele complexiteit. Vercel Edge en
`unstable_cache` zijn framework-native — nul extra infrastructuur.
Redis vraagt vendor-integratie. Postgres materialized data vraagt
invalidatie-strategie.

Bij twijfel: begin bij de eenvoudigste laag die de latency-eis dekt.
Escaleer alleen als bewezen niet-genoeg.

### Alternatieven overwogen

**Eén cache-laag voor alles.** Bijvoorbeeld: alles in Redis. Vereenvoudigt
mental model maar geeft geen edge-caching-winst en overkill voor
in-request memoization.

**Multi-laag maar automatisch geheugen-optimalisatie.** Server-side
frameworks doen dit soms (Ruby on Rails, Django). Next.js benadering
is expliciet: developer kiest welke laag past.

### Trade-off

Vier lagen betekent vier plekken waar cache-hit/miss kan gebeuren.
Debugging bij verwarrend gedrag is complexer.

Winst: elke gebruikte laag is de eenvoudigste die de behoefte dekt.

### POC-bewijs

POC ging direct naar laag 4 (Postgres materialized) zonder eerst laag
1-3 te proberen. Dat was de over-engineering die 9 issues opleverde.

---

## Beslissing 3: Geen triggers voor cache-invalidatie, ooit

### Beslissing

Cache-invalidatie is expliciete code in mutation-RPCs. Geen database-
triggers die "magisch" cache-rows deleten bij fact-mutations.

### Waarom

Triggers zijn opaque: developers zien de cache-invalidatie-logica niet
in de RPC-code. Debugging "waarom is mijn mart leeg?" wordt reconstructie
van de trigger-graph.

Triggers hebben in de POC de meeste bugs opgeleverd (ISS-100 UPDATE
vergeten, ISS-101 race-condition, ISS-092 exception-ordering).
Expliciete code is transparant en test-baar.

### Alternatieven overwogen

**Triggers met discipline.** Werkt in principe maar bewijs uit POC is
dat de discipline moeilijk vol te houden is. Elke nieuwe developer
begrijpt niet meteen welke triggers welke cache invalideren.

**Trigger die alleen logs, invalidatie via listener-service.** Meer
lagen om te onderhouden. Compromis zonder duidelijke winst.

### Trade-off

Elke mutation-RPC moet expliciet zijn eigen cache-invalidatie doen. Bij
vergeten cache-invalidatie in een nieuwe RPC: stale cache. Discipline
in code-review nodig.

Winst: cache-logica is zichtbaar en testbaar. Geen magische bijeffecten.

### POC-bewijs

De trigger-based cache-invalidatie uit ISS-089 leverde direct ISS-100
en ISS-101 op. Elke fix-poging aan de trigger creëerde nieuwe race-
condities.

---

## Beslissing 4: Versioning-based cache-keys als hulp

### Beslissing

Wanneer een materialized cache-tabel nodig blijkt (laag 4), gebruik
we versioning-based cache-keys: hash van de bronbewegingen (bijvoorbeeld
`(tenant_id, population_version, param_version, period)`). Cache-lookup
checkt hash-match; bij mismatch wordt live berekening gedaan.

### Waarom

Traditionele cache-invalidatie ("bij mutation, delete cache-row") is
foutgevoelig — je moet elke mutation-pad kennen. Versioning-based
lookup is impliciet correct: als je de bron-data wijzigt, wijzigt de
hash, dus de cache-key komt niet meer overeen, dus de cache-hit slaagt
niet.

Cleanup gebeurt asynchroon (bijvoorbeeld weekly cron): oude cache-rijen
zonder recent gebruik worden gedropt.

### Alternatieven overwogen

**Traditionele invalidatie met triggers.** Zie beslissing 3.

**TTL-based cache.** Simpelste optie: cache met vaste vervaltijd (5 min,
1 uur). Voor sommige use-cases voldoende. Voor cascade-berekeningen die
100% actueel moeten zijn bij data-wijziging niet passend.

**Cache-versie-nummer in dim_scenario.** Elke mutation verhoogt
tenant-cache-versie; cache-key bevat dit. Werkt maar vraagt extra
schema-veld en discipline.

### Trade-off

Hash-berekening bij elke cache-lookup: kleine overhead. Cleanup-cron
moet worden onderhouden.

Winst: impliciete correctheid. Cache is nooit stale ten opzichte van
bron omdat mismatch = miss = live berekening.

### POC-bewijs

Geen POC-precedent. Dit is een specifiek patroon geïnspireerd op HTTP-
caching (etag-based) en Redis-caching (key-versioning). Bewezen patroon
in web-scale contexten.

---

## Beslissing 5: Loonkloof-decompositie als eerste cache-kandidaat

### Beslissing

Als er één berekening is die vroeg cache verdient, dan is het loonkloof-
decompositie via de Python-service. Redis-TTL (24 uur) is de eerste
poging.

### Waarom

Twee factoren maken deze berekening cache-waardig:

- Hoge kosten: 500 milliseconden tot 2 seconden per tenant per kwartaal
  (op basis van POC-metingen). Elk Python-call is een HTTP-roundtrip
  plus statistische berekening.
- Lage volatiliteit: loonkloof-analyses zijn kwartaal-cijfers. Dagelijkse
  updates zijn niet vereist.

TTL van 24 uur (of langer) betekent dat de meeste page-visits een
cache-hit hebben. Alleen de eerste visit per dag triggert een Python-
call.

### Alternatieven overwogen

**Postgres materialized voor loonkloof.** Werkt maar herintroduceert de
cache-invalidatie-problematiek. Redis-TTL is eenvoudiger.

**Precompute via cron.** Nightly job dat voor alle tenants de loonkloof
uitrekent. Werkt maar rekent voor tenants die niet gebruiken. Redis-TTL
is lazy.

### Trade-off

Redis vraagt vendor-integratie (Upstash). TTL van 24 uur betekent dat
mutations gedurende de dag niet direct in loonkloof zichtbaar zijn —
acceptable trade-off voor kwartaal-analyses.

Winst: 500ms-2s response-tijd wordt millisecond-cache-hit voor herhaalde
visits.

### POC-bewijs

POC had geen loonkloof-cache. Elke pagina-visit deed volledige
Python-call. Voor POC-verkeer prima; voor productie met 100+ tenants die
frequent de loonkloof-page bezoeken zeker een early-add.

---

## Verband met andere hoofdstukken

- Data model (hoofdstuk 5) levert de tabel-versie-hashes voor
  versioning-based cache-keys
- Python service (hoofdstuk 8) is de duurste berekening en meest
  waarschijnlijke eerste cache-kandidaat
- Testing (hoofdstuk 9) benadrukt: pgTAP-tests voor cache-invalidatie
  wanneer je die introduceert
