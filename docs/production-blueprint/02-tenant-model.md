# 2. Tenant en membership-model

De keuze voor eigen tenant-model in plaats van basejump, en de
onderliggende sub-beslissingen die daarbij horen.

---

## Beslissing 1: Eigen tenant-model in plaats van basejump

### Beslissing

In de nieuwe repo bouwen we een eigen minimalistisch tenant-model met
drie kern-entiteiten: users, tenants, en memberships (N:M met rol).
Basejump wordt niet meegenomen.

### Waarom

Basejump v0.0.3 heeft ons in de POC een snelle start gegeven — auth,
teams, invitations, Stripe-billing waren direct beschikbaar. Voor een
POC is dat de juiste keuze. Voor productie werd de last echter groter
dan de baat:

- Multi-membership is niet first-class in basejump's model. Dat leidde
  in de POC direct tot ISS-098 (multi-membership cross-tenant destructie).
  Het fixen vereiste retrofit-werk in meerdere flows.

- Basejump v0.0.3 wordt niet actief onderhouden. Elke security-fix is
  onze eigen verantwoordelijkheid, elke Supabase-versie-upgrade een
  potentiële breaking change.

- We hebben ondertussen 40% van basejump al aangepast of overschreven
  in eigen migrations. De 60% die er nog van staat is niet zo groot
  meer dat een eigen model onhaalbaar is.

### Alternatieven overwogen

**Blijven op basejump.** Kortste pad. Faalt op multi-membership-eisen en
op de onderhoudsvraag. Voor middelgrote SaaS werkt basejump goed zolang
je in zijn contract past.

**Clerk of WorkOS als managed auth.** Delegateert user-management,
memberships, SSO, en billing-integratie aan een vendor. Voor teams die
liever niet zelf tenant-model bouwen is dit de duidelijke keuze. Nadeel:
je bent afhankelijk van hun API-shape, hun uptime, hun tarief-model.
Voor enterprise-klanten met specifieke identity-brokering-eisen kan
WorkOS de betere keuze zijn, maar we hebben die eisen nog niet.

**Auth.js (Next-Auth).** Werkt goed voor sessie-management en OAuth
maar levert geen tenant/membership-model — dat moet je alsnog zelf
bouwen. Winst boven Supabase Auth is beperkt.

### Trade-off

Eigen model bouwen kost ontwikkelinspanning: schema, RPCs, invitations-
flow, tests, integratie met Supabase Auth. In ruil krijg je een model
dat exact past bij het domein (multi-membership, Belgische
tenant-vereisten, roles die passen bij accountants-workflow) en geen
externe library die kan verouderen.

Voor een team dat basejump al niet passend vindt, is deze investering
per definitie de moeite waard omdat de alternatieve refactor-cost
groter is. Voor een team met minder domein-specifieke eisen kan een
managed oplossing (Clerk, WorkOS) een goede shortcut zijn.

### POC-bewijs

ISS-098 was een retrofit-fix voor iets dat vanaf dag 1 first-class had
moeten zijn. De multi-membership-aanname in basejump matcht niet met
onze werkelijkheid waar accountants voor meerdere klant-organisaties
tegelijk werken.

---

## Beslissing 2: Multi-membership als first-class citizen

### Beslissing

Een user kan lid zijn van meerdere tenants. URL-structuur `/[tenantSlug]/...`
maakt de actieve tenant expliciet in elke request. Elke server-side
operatie resolvet slug → tenant_id via een membership-check.

### Waarom

Doelgroep zijn accountants en HR-consultants. Zij werken voor meerdere
klanten tegelijk. Als tenant-scope niet in de URL zit, moet elke
data-flow ergens een impliciete tenant-selectie maken. Die impliciete
selectie is de exacte bron van ISS-098: een `.limit(1)` op RLS-
gefilterde data geeft geen deterministisch resultaat.

Slug in URL heeft naast correctheid ook UX-voordelen: deep-linkable
(accountants kunnen URLs delen met collega's), browser-history werkt
per-tenant, sessie-switch van tenant A naar B is een navigatie in plaats
van state-management.

### Alternatieven overwogen

**Tenant impliciet uit sessie.** User's "active tenant" leeft in
session-state, wordt aangepast via een switcher. Werkt voor apps waar
users bijna nooit switchen. Voor accountants die tussen klanten wisselen
elk uur: friction en verwarring welke tenant actief is.

**Sub-domein per tenant.** `klant-a.stratarius.be` in plaats van
`stratarius.be/klant-a`. Werkt maar vereist wildcard SSL, DNS-management,
en complexer session-handling. Voor Belgische SaaS zonder white-label
requirement geen duidelijke winst.

### Trade-off

Elke server-side operatie moet de tenantSlug uit URL resolven naar
tenant_id. Dat is een extra roundtrip per request (weliswaar
gecached-baar). Middleware-patroon vangt dit op zodat het niet per
page-view hoeft herhaald.

Kleine complexiteit-toename in de app-code, ruime winst in
correctheid-garanties.

### POC-bewijs

ISS-098 in vier verschillende files (import-action, clear-populatie-action,
loonkloof/page, scenarios/page). Elke file had zijn eigen impliciete
tenant-aanname. Retrofit vereiste consistent alle files aan te passen.

---

## Beslissing 3: Roles als kolom op membership, niet als aparte tabel

### Beslissing

Elke membership heeft één role (owner, admin, member, viewer) als kolom.
Geen aparte roles/permissions-tabel.

### Waarom

Voor middelgrote B2B SaaS met vier niveaus is een fine-grained
permissions-systeem overkill. Vier levels dekt de praktische scenarios:
- Owner: billing, tenant-lifecycle
- Admin: alle data-mutaties, invitations
- Member: data-mutaties zonder invite-rechten
- Viewer: readonly

RPC-authorization check is dan een membership-lookup met role-in-array
match. Simpel, testbaar, transparant.

### Alternatieven overwogen

**Fine-grained permissions (RBAC/ABAC).** Losse permissions-tabel,
role-permission mapping, evaluatie per RPC. Krachtig maar veel
overhead voor 4 niveaus. Waardevol als je custom rollen per tenant
wilt ondersteunen — voor Stratarius nog niet in beeld.

**Enum-based roles.** Zelfde als rol-kolom maar met Postgres enum type.
Marginaal type-safer maar migratie bij nieuwe rol vereist alter-type.
Text met check-constraint is flexibeler.

### Trade-off

Als je later een 5e rol nodig hebt, is dat een migration en een update
van check-constraint. Als je later per-tenant custom rollen nodig hebt,
is dat een groter refactor. Beide scenarios zijn nu niet gepland.

### POC-bewijs

Basejump had een vergelijkbare `account_role` kolom. Werkte prima voor
de use-cases die de POC dekte. Geen bugs in role-checking, alleen in
tenant-resolution.

---

## Beslissing 4: Invitations via signed tokens met TTL

### Beslissing

Uitnodigen gebeurt door insertie in een `invitations` tabel met een
cryptografisch signed token en een expiry-datum (7 dagen). Bij accept:
membership wordt aangemaakt, invitation gemarkeerd als geaccepteerd.

### Waarom

Signed tokens (HMAC met server-secret) voorkomen dat een aanvaller
tokens kan raden of vervalsen. TTL beperkt de window voor stolen-link-
attacks.

Insertie in Postgres houdt de invitation zichtbaar voor de owner
(dashboard: "pending invitations for this tenant"). Alternatief zou zijn
om alles via email-links te doen zonder DB-state, maar dan verlies je
de "wie is uitgenodigd, wie heeft nog niet geaccepteerd"-view.

### Alternatieven overwogen

**JWT-based invitations zonder DB-state.** Token bevat alle info
(tenant, email, role, expiry) signed door server. Voordeel: geen DB-
lookup. Nadeel: geen zichtbaarheid van pending invitations, geen
mogelijkheid om te revoken vóór expiry.

**OAuth-style verification codes** (6-digit code in email). Simpler
voor user, maar vereist entering. Voor B2B accountants-tools is een
click-link workflow standaard verwachting.

### Trade-off

DB-tabel voor invitations betekent kleine extra opslag en een migration.
Grote winst in beheerbaarheid (revoke pending, view outstanding).

### POC-bewijs

Basejump had een vergelijkbare `invitations` tabel. Werkte prima. Geen
issues in de reviews.

---

## Beslissing 5: Session-context via helper-function

### Beslissing

Een helper-function `current_user_id()` mapt `auth.uid()` (Supabase Auth)
naar de business-user in `public.users`. Wordt op de RPC-boundary
gecached binnen dezelfde transactie.

### Waarom

Supabase Auth beheert authentication, wij beheren business-users
(profielinformatie, membership-relaties). De koppeling tussen beide
gebeurt in `public.users.auth_id`.

RPCs willen weten "welke business-user roept mij aan". Direct
`auth.uid()` gebruiken zou betekenen dat we auth-ids overal in queries
laten leken. Beter: dedicated helper die één laag isolatie geeft.

Caching binnen transactie voorkomt herhaalde lookups in dezelfde
request.

### Alternatieven overwogen

**auth.uid() direct gebruiken.** Werkt maar knoopt onze business-tabellen
vast aan Supabase Auth's auth.users tabel. Bij eventuele auth-vendor-
switch wordt dit refactor-werk.

**JWT-claims uitbreiden met business-user-id.** Custom claim in het
access-token. Werkt maar vraagt server-side hook (Supabase Auth
custom_access_token hook). Meer moving parts. Sneller in read-heavy
scenarios omdat geen DB-lookup nodig is, maar de meeste RPCs doen
sowieso DB-work.

### Trade-off

Extra DB-lookup per request voor de user-resolve. Verwaarloosbaar in
absolute tijd; wel een implementation-detail om in gedachten te houden.

### POC-bewijs

Basejump gebruikte `auth.uid()` direct in policies en RPCs. Werkte
functioneel maar bemoeilijkt eventuele auth-vendor-switch. Voor
productie is dedicated helper een goede investering.

---

## Verband met andere hoofdstukken

- RPC-only surface (hoofdstuk 4) leunt op de tenant-check patterns uit
  dit hoofdstuk
- Startup-volgorde (hoofdstuk 10) plaatst tenant-model in laag 5,
  direct na auth
- Wanneer-niet (hoofdstuk 12) noemt Clerk/WorkOS als valide alternatief
  voor teams zonder domein-specifieke eisen
