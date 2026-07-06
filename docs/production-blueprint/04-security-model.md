# 4. Security-model — RPC-only

Uitwerking van principe 1 uit hoofdstuk 1. Alle domein-toegang via
SECURITY DEFINER RPCs, met bijhorende sub-beslissingen over audit,
PII-encryption en rate limiting.

---

## Beslissing 1: REVOKE alle directe grants op domein-tabellen

### Beslissing

Op elke tenant-scoped domein-tabel wordt `REVOKE ALL` toegepast voor de
rollen authenticated, anon en public. Alleen `service_role` heeft
directe SELECT/INSERT/UPDATE/DELETE voor operationele scripts. RLS
blijft aan als tweede laag.

### Waarom

De basejump-default (directe grants aan authenticated + RLS-policy)
werkt goed voor middelgrote apps. Voor payroll met GDPR-eisen en
multi-membership faalt het: authenticated kan direct queries doen die
de RPC-audit-laag omzeilen (ISS-089, ISS-099).

REVOKE maakt de RPC de enige toegangsweg. Elke domein-touch heeft
dan gegarandeerd de audit-context die de RPC vestigt.

RLS blijft aan als goedkope tweede laag: als een SECURITY DEFINER
RPC per ongeluk een verkeerde tenant leest, RLS is niet actief (DEFINER
bypasst RLS), maar tenant-users kunnen sowieso niet direct queryen.

### Alternatieven overwogen

**Direct grants + RLS + RPC (POC-aanpak).** Werkt tot je multi-membership
of column-level PII toevoegt. Voor de POC-context prima, voor productie
gevalideerd risicovol.

**Read-alleen grants, writes via RPC.** Compromis-oplossing. Reads zijn
snel (geen RPC-overhead) maar audit-log is incompleet voor reads. Voor
apps waar reads geen PII raken kan dit werken. Voor payroll waar bijna
elke read een PII-vraag is niet passend.

### Trade-off

Elke read en write wordt een RPC-call. Dat is meer boilerplate en
marginaal meer latency dan direct-query. Voor ontwikkelaars die van
Prisma-stijl development komen is dit een aanpassing.

Wat je terugkrijgt: gegarandeerde audit-log, één security-model,
consistente tenant-scoping, geen ISS-089-achtige bugs.

### POC-bewijs

Migration `20260703350000_fix_domain_table_grants.sql` gaf directe DML-
grants om development te versnellen. Werkte tot ISS-089 en ISS-099
bloot legden dat de grants bypass-paths creëerden.

---

## Beslissing 2: Elke RPC met expliciete tenant-parameter

### Beslissing

RPCs die tenant-scoped data raken nemen `p_tenant_id uuid` als expliciete
parameter (niet impliciet uit sessie). De RPC valideert:
1. `auth.uid()` is niet null
2. Caller is member van `p_tenant_id`
3. Voor PII-touch: `p_rechtsgrondslag` is aanwezig

### Waarom

Impliciete tenant-scope leidt tot ISS-098-achtige bugs. Expliciete
parameter dwingt de caller om na te denken over welke tenant. De
resolver in de frontend (`resolveTenant` uit hoofdstuk 2) doet die
resolve op één plek; alle RPCs krijgen de tenant-id door.

Rechtsgrondslag als parameter is Belgische compliance-eis: elke PII-
touch moet vastleggen op welke wettelijke basis het gebeurt. Als het een
parameter is, kan de RPC weigeren als hij ontbreekt.

### Alternatieven overwogen

**Tenant impliciet uit session context.** Set een session-variable bij
login met de "actieve tenant". RPCs lezen die impliciet. Werkt als users
één tenant tegelijk actief hebben. Voor multi-membership breekt dit
model: je moet altijd expliciet zijn over welke tenant.

**Rechtsgrondslag als default.** RPC heeft een default-value voor
rechtsgrondslag. Werkt technisch maar mist de dwingende factor: default-
values worden gebruikt zonder na te denken.

### Trade-off

Elke RPC-call in de frontend moet de tenant-id meesturen. Dat is een
extra parameter overal. Repetitief, maar consistent.

Wat je terugkrijgt: onmogelijkheid om per ongeluk cross-tenant te
opereren; gegarandeerde rechtsgrondslag-log voor GDPR.

### POC-bewijs

`cascade_populatie_snapshot` heeft `p_scenario_id` als parameter en
resolvet daaruit de tenant. Werkte omdat scenario_id 1-op-1 uniek is
naar tenant. Voor operaties zonder duidelijke scenario-referentie
(zoals refresh_mart_loonkloof, ISS-091) was tenant-parameter alsnog
nodig — retrofit.

---

## Beslissing 3: Audit-log als append-only immutable

### Beslissing

Een tabel `audit_log` legt elke PII-touch vast: user_id, tenant_id,
action (RPC-naam), rechtsgrondslag, columns_accessed, timestamp. Insertie
alleen via `SECURITY DEFINER` helper. Geen UPDATE- of DELETE-policy
voor niemand behoudens service_role.

### Waarom

GDPR verplicht log van PII-access. Belgische fiscale wet vraagt 7 jaar
bewaring. Als de audit-log muteerbaar is, kan hij worden vervalst — en
dan is hij juridisch waardeloos.

Append-only + geen mutatie-policy maakt de log werk-mate onaantastbaar
door normale users. Alleen service_role (voor archivering of
partitionering) heeft schrijf-rechten anders dan de insertie-helper.

### Alternatieven overwogen

**Cryptografic hash-chain over audit-rows.** Elke rij bevat hash van
vorige rij. Externe auditor kan chain valideren. Extra tamper-detection.
Voor eerste versie overkill; voor enterprise-klanten met scherpe
compliance-eisen op roadmap. Kan later worden toegevoegd zonder de
huidige rows te breken.

**Audit-log naar S3 buiten Postgres.** Volledig immutable (versioning
in S3). Nadeel: query-heavy audit-analyses worden trager. Voor
grote-scale audit-load nuttig, voor de meeste tenants overkill.

### Trade-off

Append-only tabel groeit onbeperkt. Bij 100 tenants met 1000 events per
dag wordt dat tientallen miljoenen rijen per jaar. Vraagt partitionering
en archivering-beleid — pg_partman voor monthly partitions, oude
partitions naar S3 na 2 jaar.

Grote winst: audit-integriteit is technisch afgedwongen, niet alleen
policy.

### POC-bewijs

POC had `gdpr_access_log` tabel met dezelfde principes. Werkte functioneel.
Insert-only via helper-functie is patroon dat we behouden.

---

## Beslissing 4: Column-level encryption voor gevoelige PII

### Beslissing

Kolommen met bijzonder gevoelige PII (geboortedatum, geslacht, ondernemings-
nummer, IBAN) worden versleuteld met `pgcrypto` en een KMS-managed key.
Decryptie alleen in geautoriseerde read-RPCs.

### Waarom

Belgische regelgeving en beste-praktijk verlangen bescherming van PII
"at rest". Database-backups die in verkeerde handen vallen, admin die
per ongeluk teveel toegang heeft, of gecompromiteerde credentials —
column-encryption dekt deze scenarios.

Deze bescherming werkt bovenop RLS + REVOKE + audit: het is de laatste
laag als andere lagen falen.

### Alternatieven overwogen

**Volledige database-encryption at rest.** Standaard bij managed
Postgres (Supabase). Beschermt tegen storage-diefstal maar niet tegen
admin-access of gecompromiteerde credentials. Column-level is
strikter.

**PII in aparte database.** Sensitive velden in dedicated encrypted
tabel of database. Sterk isolatie maar significant meer infrastructuur.
Voor scherpe compliance-eisen (SOC 2 Type 2) een overweging waard.

**Geen encryption, alleen RLS + audit.** Werkt technisch tot een
incident. Voor payroll-app met Big-4 klanten mogelijk juridisch
onvoldoende.

### Trade-off

Encryption + decryption is CPU-overhead per query. Voor kleinere PII-
kolommen verwaarloosbaar, voor grote velden merkbaar. Key-rotation is
operationele complexiteit — moet worden gepland.

Grote winst: PII-bescherming is meerlaags. Backups zonder key onbruikbaar.

### POC-bewijs

POC had column-REVOKE als bescherming (ISS-086). Werd omzeild via mart-
replicatie (ISS-099). Column-encryption zou beide problemen hebben
opgelost want mart-replicatie zou de encrypted data hebben gekopieerd
zonder key.

---

## Beslissing 5: Rate limiting op meerdere lagen

### Beslissing

Rate limiting wordt toegepast op drie lagen: edge (Cloudflare of Vercel
Edge — globaal DDoS), middleware (per-user via Upstash Redis), en
optioneel in de RPC zelf (per-tenant voor extra-dure operaties).

### Waarom

Één laag is nooit voldoende. Edge stopt volume-attacks. Middleware
beschermt tegen abuse door legitieme users. RPC-laag beschermt Postgres
tegen queries die per-tenant te vaak worden aangeroepen.

Concrete rate-limit-getallen zijn afhankelijk van verwachte usage-
patronen. Bij ontbreken van productie-data: begin met redelijke defaults
(bijvoorbeeld 100 req/min per user globaal, 20 req/hour voor Python-
service calls) en pas aan na monitoring.

### Alternatieven overwogen

**Alleen edge-limiting.** Werkt tegen DDoS maar niet tegen legitiem-
lijkend abuse (bijv. iemand die 1000 imports per uur triggert). Voor
B2B SaaS onvoldoende.

**Alleen RPC-level limiting.** Werkt maar mist edge-DDoS-bescherming.
Vercel/Cloudflare hebben deze bescherming ingebouwd; niet gebruiken is
geld weggooien.

**In-Postgres advisory-lock-based limiting.** Werkt maar concurrent
lock-vraag kan zelf Postgres belasten bij hoge volumes. Redis is
efficiënter voor rate-state.

### Trade-off

Meer infrastructuur (Redis-integratie) en meer configuratie. Vraagt
monitoring om te weten of limits te strak of te ruim zijn.

Grote winst: bescherming tegen abuse, cost-control (Python-service
calls zijn kostbaar), en per-tenant fairness.

### POC-bewijs

POC had geen rate limiting. Voor demo-context prima. Bij eerste
productie-tenants is dit een noodzakelijke early-add omdat een enkele
klant je Python-budget kan opeten voor de rest.

---

## Verband met andere hoofdstukken

- Tenant-model (hoofdstuk 2) levert de `is_member_of` en `has_role`
  helpers die RPCs gebruiken
- Data model (hoofdstuk 5) beschrijft de PII-kolommen die encryption
  krijgen
- Operations (hoofdstuk 11) werkt de rate-limit-getallen uit voor
  verschillende operatie-types
