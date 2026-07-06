## Wat er deze sessie gebeurd is

Twee blokken bovenop de "cache-materialization + UI-polish"-sessie:

**Blok A — POC-checkpoint review met parallel Claude + Codex.** Na de UI-polish-slag hebben we een multi-agent review gedraaid op de eindstand. 3 Claude review-agents parallel (cache architectuur, silent failures, RLS + type safety) + 1 onafhankelijke Codex-review met een uitgebreide prompt (`_supporting-material/reviews/codex-review-prompt.md`). Rules of engagement: read-only, geen edits, geen commits, expliciet géén `storybloq_issue_create` — output alleen als markdown. De consolidatie-stap (convergentie/divergentie-tabel) leverde 10 concrete findings, gerankt op severity en confidence.

**Blok B — Issue-sweep: 10 issues fixed en resolved (ISS-088 t/m ISS-097).** Twee prod-blockers vielen op: `clear_tenant_populatie` had een RPC signature mismatch (Claude Agent 2+3 convergent) en scenario-RPCs (`create_what_if_scenario`, `create_wagen_scenario`, `create_scenario_with_mutations`) misten volledig een `has_role_on_account` tenant-check (Codex-uniek, ISS-088). Plus tijdens de sweep werd 1 extra prod-bug ontdekt tijdens user-test: `clear_tenant_populatie(uuid)` was door drop-overload zijn `GRANT EXECUTE` kwijt (commit `4399800`).

## Prod pushes deze sessie

Alle 10 commits gepusht naar main + 8 migrations toegepast op prod-DB:

- `00e9992` fix(security): ISS-088 — scenario-RPCs tenant validation + baseline check
- `4399800` fix(db): grant execute op clear_tenant_populatie(uuid)
- `6b6ebb5` fix(cache): ISS-089 + ISS-092 — statement-level triggers voor mart invalidation
- `4de97a4` fix(cache): ISS-091 — refresh_mart_loonkloof scope naar single tenant
- `6497bf3` fix(rls): ISS-093 — mart_loonkloof_decomp view security_invoker
- `20791fa` fix(ui): ISS-090 — surface cache/refresh failures ipv 'geen data' fallback
- `7dbdc79` fix(cache): ISS-094 — concurrent cache-refresh safety (advisory lock + ON CONFLICT)
- `11e7c9f` fix(cache): ISS-095 — param_* mutations invalidate alle mart-caches
- `b9e5b26` fix(setup): ISS-096 — atomische setup via complete_tenant_setup RPC
- `6cfe8ee` refactor(types): ISS-097 — extract populatie types naar -types.ts

## Belangrijke architecturale patterns na deze sessie

**Cache-invalidatie is nu 3-lagig (defense in depth):**
1. Mutation-RPCs invalideren expliciet (bestaand, ISS-089+092 aanpak)
2. Statement-level triggers op alle tenant-scoped tabellen — fangen directe DML + Supabase Studio ad-hoc edits + mid-transactie crashes (via rollback-atomicity)
3. Statement-level triggers op alle 13 param_* tabellen — TRUNCATE beide marts globaal bij parameter-wijziging (adressen freshness contract)

**SECURITY DEFINER RPC template:**
Elke tenant-touching RPC volgt nu dit patroon (uit `cascade_populatie_snapshot` commit 3343d8f):
- `auth.uid()` check
- Owning-account lookup via `dim_legale_entiteit`
- `basejump.has_role_on_account(v_owning_account)` check
- Als baseline of tweede-tenant ref (bijv. `p_baseline_scenario_id`): tenant-match check
- Optionele `pg_advisory_xact_lock` voor concurrency-safety
- `gdpr_access_log` audit met eigen exception block

**Concurrency-safety patroon voor cache-refresh:**
`pg_advisory_xact_lock(hashtextextended(scope_key, salt))` aan begin van refresh-RPC + `ON CONFLICT (pk_cols) DO NOTHING` op INSERT. Serialiseert voor dezelfde scope, laat verschillende scopes parallel lopen.

## Where to pick up

**Alle 10 issues resolved. Alle 58 tickets nog steeds af. Geen open issues.** Volgende richtingen:

1. **Bevestig prod-fixes werken end-to-end.** Clear-populatie was 2x kapot deze sessie — verifieer in browser dat het nu ook echt werkt na de db-push. Zelfde voor scenario-creatie (nieuwe tenant-checks).
2. **Post-POC: alle mutations door SECURITY DEFINER RPCs met REVOKE als hardening.** ISS-096 hield de directe DML-grants op `dim_legale_entiteit` en `dim_scenario` bewust in stand omdat tests 23/30 die verifiëren. Bredere refactor: alle mutations via RPCs, REVOKE directe grants, tests aanpassen.
3. **Supabase typegen-workflow opzetten.** ISS-097 liet `as unknown as PopRow[]` casts staan omdat dat een typegen-workflow vereist. Post-POC: `supabase gen types` + generated types in `src/types/database.ts`.
4. **Basejump `prevState: any` opruimen** — bewust out-of-scope gelaten (legacy code) maar wel de laatste `any` in `src/lib/actions/`.
5. **DMFA-aangifte / echte productionization** — nieuwe fase, groter werk.

## Belangrijke context voor de volgende sessie

- **`clear_tenant_populatie` signature:** nu `(p_legale_entiteit_id uuid)`, return `deleted_contracten`/`deleted_personen`. Oude 2-arg overload (met `p_rechtsgrondslag`) is gedropt. Client stuurt geen rechtsgrondslag mee (audit staat in RPC zelf).
- **`refresh_mart_loonkloof` signature:** nu `(p_owning_account_id uuid, p_rechtsgrondslag text)`. Vraagt EXPLICIETE tenant, geen "auto-fetch all caller's tenants" meer. Client haalt owning_account_id op via `get_account_by_slug(accountSlug)`.
- **Cache-triggers doen mart-DELETE binnen dezelfde transactie als de triggering mutation.** Bij rollback rolt cache-invalidatie mee — cache blijft coherent met source. Dit betekent ook dat de expliciete `DELETE FROM mart_*` aan het eind van `bulk_import_populatie` en `clear_tenant_populatie` nu redundant maar semantisch veilig zijn (defense-in-depth).
- **Advisory lock hash salts:** 42 voor `refresh_populatie_loonkost_cache`, 43 voor `refresh_mart_loonkloof`. Verschillende salts zodat dezelfde tenant's populatie- en loonkloof-refresh niet elkaar blokkeren.
- **`param_*` triggers TRUNCATE marts globaal.** Elke param-migratie triggert een cache-miss op eerstvolgende page-visit per tenant. Bewust breed — parameter-migraties zijn zeldzaam (jaarlijkse RSZ-update).
- **`mart_loonkloof_decomp` view heeft nu `security_invoker=true`.** Directe SELECT respecteert RLS van caller. RPC `mart_loonkloof_decomp_read` blijft canonieke access-path met extra audit.
- **`complete_tenant_setup(p_owning_account_id, p_naam, p_gewest, p_werkgeverscategorie, p_ondernemingsnr, p_baseline_naam)`** vervangt de compensating-delete pattern in setup-action.ts. Atomair, has_role_on_account check, input validation in RPC.

## Nog gevonden maar niet gefixt

- **`as unknown as PopRow[]` casts** in populatie-results.tsx blijven (ISS-097 partial). Fix vraagt Supabase typegen-workflow — post-POC follow-up.
- **Basejump `prevState: any`** in billing/invitations/members actions blijft. Legacy imported code, buiten scope.
- **REVOKE directe DML op `dim_legale_entiteit` + `dim_scenario`** niet toegepast. Zou tests 23/30 breken. Follow-up: alle mutations via RPCs.

## Meta-observatie

Codex-review vond ISS-088 solo — Claude miste dit terwijl 3 agents parallel dezelfde codebase deden. Dit is het meest waardevolle bewijs voor de "twee onafhankelijke reviewers > één"-hypothese in dit project. Zie ook lesson (nieuw aangemaakt deze sessie).
