# Handover — Foundation phase compleet (T-039, T-040)

**Session**: aa7d8969 (targeted auto)
**Tickets completed**: 2/2 (T-039, T-040)
**Commits**: b624d5b, 7065311
**Branch**: main

## Wat is er gebeurd

**T-039** — team-only tenant model (medium scope)
- Migration `20260703000000_disable_personal_account_billing.sql` zet `basejump.config.enable_personal_account_billing = false`
- UI-hide van personal accounts in workspace-selector (account-selector.tsx, navigation-account-selector.tsx) en user-account-button dropdown (Settings + Teams items verwijderd)
- **Scope pivot mid-session**: originele plan was hard-delete van (personalAccount)/ tree en nieuwe /dashboard/page.tsx + /create-team/page.tsx. User redirect: "disablen was genoeg, verwijderen niet". Rollback via git checkout; (personalAccount)/ tree behouden. Consistente softe enforcement.

**T-040** — billing UI hide (medium scope)
- Beide settings-layouts: "Billing" menu-item verwijderd uit items array
- Beide billing/page.tsx overschreven met 3-regel server-side redirect naar parent settings
- billing-functions/, billing-webhooks/, migration, actions/billing.ts, AccountBillingStatus component allemaal behouden per N-005 "behouden, disabled"

## Belangrijke beslissing/patroon

**Medium-scope enforcement is de nieuwe standaard voor Basejump-boilerplate-tickets**. Voor Phase 1-3 (foundation + schema) is dit patroon prima:
- Hide UI paths (menu items, dropdown items, workspace selectors)
- Redirect URL-hacked pages naar hun parent
- Code, migrations, edge functions blijven op disk voor gemakkelijke add-back

Hard-delete is bewaard voor het geval een feature echt onlogisch wordt met de code aanwezig. Voorwaarde: expliciet in ticket spec.

## Volgende stappen

Foundation phase (5/5) is nu compleet:
- T-001 (proxy consolidate) ✅
- T-002 (demo cleanup) ✅
- T-003 (.env.example) ✅
- T-039 (personal accounts hide) ✅
- T-040 (billing UI hide) ✅

**Phase 2 (schema-ruggengraat) staat open**:
- T-004: dim_persoon + dim_functie (unblocked)
- T-005: dim_legale_entiteit + dim_land (blocked op T-004 + T-039 — T-039 nu klaar, dus zodra T-004 done is T-005 unblocked)
- T-006: dim_contract (blocked op T-004 + T-005 + T-007)
- T-007: dim_pc (unblocked)
- T-008: dim_org_unit + hierarchie (blocked op T-005 + T-007)
- T-009: named hierarchy views (blocked op T-008)

**Aanbevolen volgende sessie**: `/story auto T-004 T-007` — twee unblocked schema-migraties, geen deps, kunnen parallel. Daarna cascade T-005 → T-008 → T-009.

**Overweging**: Phase 2 raakt geen rekencascade of parameterlaag, dus Constitution Principe V TDD is nog niet non-negotiable. Basejump pgTAP tests (`supabase/tests/database/`) zijn wel goede referentie — kan aangeraden zijn om domain-schema tests toe te voegen als extra veiligheid, maar niet strict verplicht.

**Open decisions** die T-004..T-009 niet blokkeren:
- N-001 (legal source acquisition) — relevant bij T-018/019/020 in Phase 4
- N-002 (parameter freshness SLA) — Phase 4
- N-004 (historical data volume) — Phase 4
- N-006 (UI language) — Phase 7
- N-008 (OLS tooling) — Phase 6
- N-009 (deployment target) — pre-launch

## Reviewer findings van deze sessie (deferred / auto-filed)

ISS-007..ISS-009 (of vergelijkbaar) auto-gefilede uit deferred plan/code review findings. Geen blockers voor Phase 2 start.