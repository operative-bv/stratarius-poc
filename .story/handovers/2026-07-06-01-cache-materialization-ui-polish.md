## Wat er deze sessie gebeurd is

Twee blokken werk boven op de "60/60 pgTAP + alle ISS gesloten"-sessie:

**Blok A — cascade output materialiseren (5 commits).** De cascade werd tot nu op elke page-visit opnieuw berekend. Voor 27 rijen prima, maar niet schaalbaar. Nu heeft `mart_populatie_loonkost` een persistente tabel met `owning_account_id` + RLS-policy (`has_role_on_account`), gerefreshed via `refresh_populatie_loonkost_cache(periode, scenario_id)` SECURITY DEFINER RPC met tenant-check + audit-log. Zelfde patroon toegepast op `mart_loonkloof`: was materialized view (RLS-incompat), nu tabel met per-tenant delete+insert refresh. Auto-populate on cache miss (empty → refresh → re-query) en **auto-invalidatie via `bulk_import_populatie` + `clear_tenant_populatie`** — geen refresh-button meer, want alle mutaties gaan via onze eigen RPCs, dus wij weten wanneer data verandert.

**Blok B — UI-lens sweep (4 commits).** Multi-entiteit picker op de loonkloof-page (URL-searchParam `?entiteit=`), jargon purge (schemanamen zoals `mart_loonkloof`, `fact_loonkost` weg uit UI-teksten, cascade-stap-verwijzingen weg, "banker's rounding"/"RLS filtert automatisch op tenant" weg), shadcn composition (Card ipv raw bordered divs, Collapsible ipv `<details>/<summary>`, `size-*` ipv `h-N w-N`), en accessibility polish (sr-only labels op ghost icon buttons in basejump, TableHeader/TableHead op manage-team-* tables, `text-blue-500` op links naar `text-primary`, `text-red-600` naar `text-destructive`).

## Prod pushes deze sessie

- `5925265` feat(populatie): mart_populatie_loonkost cache — persistent cascade output
- `67becc3` fix(cache): auto-populate mart_populatie_loonkost bij eerste page-visit
- `6d02ec9` refactor(cache): auto-invalidate mart_populatie_loonkost via mutatie-RPCs
- `27b2bcb` refactor(db): cleanup dead code + mart_loonkloof naar tabel + RLS
- `99dbc34` fix(loonkloof): auto-populate mart_loonkloof bij eerste page-visit
- `58856a4` feat(loonkloof): multi-entiteit picker + per-entiteit view
- `2b7f483` refactor(ui): purge schema-namen, tickett refs en cascade jargon uit UI
- `c2e65e6` refactor(ui): shadcn composition — Card + Collapsible + size-* icons

**Lokaal, nog niet gepusht:** `0d361fa` refactor(ui): polish sweep — a11y, hardcoded colors, table headers

## Belangrijke architecturale beslissingen

**Regular tables ipv materialized views voor caches.** Materialized views + RLS zijn incompatibel in Postgres (MV wordt door owner geëxecuteerd, ziet ALLE rijen). Gekozen voor tabel + `owning_account_id` kolom + RLS-policy + per-tenant refresh RPC. Zelfde model voor `mart_populatie_loonkost` én `mart_loonkloof`.

**Cache invalidation als architectural side effect van mutation RPCs.** In `bulk_import_populatie` en `clear_tenant_populatie` staat nu een `DELETE FROM mart_populatie_loonkost WHERE owning_account_id = ...` + `DELETE FROM mart_loonkloof WHERE owning_account_id = ...`. Alle mutaties gaan via die twee RPCs; zolang dat zo blijft is de cache automatisch coherent. Geen refresh-button, geen scheduled job, geen cache TTL.

**Structurele fix ISS-077 (mart_loonkloof cross-tenant leak).** Was tijdelijk gefixt via app-side `entiteit_ids` filter — nu native RLS enforced. `mart_loonkloof_decomp` view + `mart_loonkloof_decomp_read` RPC opnieuw aangemaakt bovenop de nieuwe tabel.

**Numeric field overflow fix.** `create_simulator_scenario` had `numeric(6, 4)` cast op `uren_per_maand`; 173.33 overflowde. Nu `numeric(10, 4)` (matcht `fact_prestatie.uren` kolomtype).

## Database cleanup dat is gedaan

Verwijderd:
- `mart_refresh_log` + `run_scheduled_mart_refresh` (dood, geen caller)
- `param_extralegaal_override` + `resolve_extralegaal_taks` (dood, geen caller)
- `fact_loonkost` + `create_populatie_loonkost` (vervangen door cache-tabel)
- `mart_loonkloof` materialized view + `mart_loonkloof_decomp` view + read-RPC (vervangen door tabel-versie)

pgTAP tests bijgewerkt: 4 dead-code test files gedeleted (39, 60, 62, 64), test 63 plan 6→5, test 57 fact_loonkost cascade delete weg, test 38 counts 14→13.

## Where to pick up

Alle 58 tickets nog steeds af, 0 open issues, geen TaskList tasks. Handover-punten:

1. **`0d361fa` push naar main** — polish sweep commit staat lokaal. Auto-mode blokkeerde push in deze sessie.
2. **Ultrareview op main** — de user wilde deze sessie een `/ultrareview` op de recente changes draaien. Nog niet gedaan.
3. **Nieuwe fase openen** als volgende scope: "Productionization" (echte OAuth-tenant onboarding, backup strategy, monitoring, DmfA-aangifte), of "HR-systeem koppelingen" (Workday, BambooHR, SD Worx, Attentia — roadmap Q3-Q4 2026 zoals in DEMO_SCRIPT.md).

## Belangrijke context voor de volgende sessie

- **Cache invalidation contract:** elke nieuwe mutatie-RPC die `dim_persoon`, `dim_contract`, `fact_looncomponent`, `dim_functie` of param_* tabellen wijzigt MOET `DELETE FROM mart_populatie_loonkost WHERE owning_account_id = X` + `DELETE FROM mart_loonkloof WHERE owning_account_id = X` toevoegen. Anders divergeren cache en source.
- **Auto-populate patroon:** Server Component leest cache; als leeg → call refresh RPC → herquery. Dit patroon staat in `dashboard/[accountSlug]/populatie/page.tsx` en `loonkloof/page.tsx`.
- **Multi-entiteit picker:** `EntiteitFilter` client component (`src/components/loonkloof/entiteit-filter.tsx`) push `?entiteit=<id>` searchParam; page.tsx leest `entiteitFilter` en past query aan. "Alle entiteiten" toont aggregate warning banner.
- **UI jargon-conventie na deze sessie:** geen schema-namen (`mart_*`, `fact_*`, `dim_*`), geen ticket-refs (`T-004`, `ISS-*`), geen cascade-stap-namen (`stap 4 doelgroepverminderingen`) in user-facing UI. Wel intern in code, comments, migrations.
- **shadcn composition-defaults na deze sessie:** Card composition ipv raw bordered divs, Collapsible ipv `<details>`, `size-N` ipv `h-N w-N`, `text-primary` op links (niet `text-blue-500`), `text-destructive` (niet `text-red-600`), `sr-only` label in elke ghost icon button. Basejump legacy nog niet 100% doorgevoerd — alleen de meest-visible components.

## Nog gevonden maar niet gefixt

Uit UI-lens review buiten scope gelaten (niet urgent, geen bug):
- `space-y-*` → `flex flex-col gap-*` op page-container divs (visueel identiek)
- CardContent default padding vs `pt-6` inconsistentie (kosmetisch)
- Enkele basejump Select components hebben mismatch tussen `htmlFor` label en input `id` — kleine a11y-fix
