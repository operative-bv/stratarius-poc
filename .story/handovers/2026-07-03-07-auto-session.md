# Handover — T-006 + T-008: Phase 2 Ruggengraat 5/6

**Session**: dcdd7eb8 (targeted auto, 2 tickets)
**Commits**: 2675edb (T-006), 7410c17 (T-008)

## Wat is er gebeurd

**T-006** dim_contract — de kritische ruggengraat. uuid PK, 4 FKs (persoon/functie/legale_entiteit/pc), fte_breuk numeric(6,4) 0<x<=1, effective-dated met vorige_contract_id keten. RLS via correlated subquery through dim_legale_entiteit (transitive tenant, byte-identical WITH CHECK). 4 indexes voor RLS + cascade joins. 19 pgTAP assertions incl fte_breuk boundary tests, versioning keten.

**T-008** organisatie-hiërarchie infra (4 tabellen). dim_hierarchie (4 canonieke flavors, global lookup), dim_org_unit (biconditional CHECK op kind/legale_entiteit), bridge_hierarchie (closure met dubbele RLS ancestor+descendant), map_entiteit_pc_competentie (effective-dated PC toewijzing per entiteit/activiteit/categorie). 21 pgTAP assertions incl cross-tenant WRITE-block op alle 3 domain-tables.

## Belangrijke inzichten

1. **Codex CLI eerste run test na settings update**: settings.allow verwijdert permission-prompts, MAAR auto-mode content-classifier is een tweede laag die source-piping naar external services blokkeert onafhankelijk. Codex kreeg alleen ticket-JSON in eerste diff-poging (untracked files niet in git diff); tweede poging met git add -N werd geblokkeerd. Fallback naar agent per Storybloq's instructie werkt betrouwbaar.

2. **RLS pattern diversiteit is intentional**: T-004 uses direct has_role_on_account(owning_account_id). T-006 gebruikt correlated subquery via legale_entiteit (transitive tenant, no basejump_account_id on dim_contract). T-008 bridge gebruikt BEIDE ancestor+descendant checks; map gebruikt transitive via entiteit_id. Elk patroon is architecturally justified voor de betreffende data-shape. In-migration comments waarschuwen tegen 'normalizing' via redundant owning_account_id.

3. **Biconditional CHECK op dim_org_unit** blijkt elegant patroon voor nullable-FK-with-type-tag: `kind='legale_entiteit' AND leid NOT NULL OR kind<>'legale_entiteit' AND leid NULL`. Testable in pgTAP met throws_ok 23514 op beide branches.

4. **Vercel deploy vraag** binnen deze sessie: user wil publishen op Vercel voor gemak. Post-sessie actie — zie volgende sessie plan.

## Volgende stappen

**Phase 2 Ruggengraat: 5/6 done** — alleen T-009 (named hierarchy views) resteert. Blocked op T-008 dat nu klaar is.

- ✅ T-004, T-005, T-006, T-007, T-008
- ⏬ T-009 named hierarchy views — unblocked
- Phase 3 (schema-componenten) T-010, T-013, T-014 allen unblocked

**Kritische beslissing: hoe verder?**
- **Optie A**: `/story auto T-009` — sluit Phase 2 compleet af
- **Optie B**: `/story auto T-009 T-010 T-013` — Phase 2 close + Phase 3 kickoff
- **Optie C**: Pauze Storybloq-work, help user met Vercel deploy setup (env vars, project setup, first deploy)

**Vercel deployment steps voor volgende sessie**:
1. Verify N-009 assumption: Vercel EU + Supabase managed EU (Frankfurt regio)
2. User connect GitHub repo aan Vercel dashboard
3. Env vars overzetten uit .env.example (NEXT_PUBLIC_SUPABASE_URL, ANON_KEY, SERVICE_ROLE_KEY, NEXT_PUBLIC_URL) via Vercel dashboard — met production URL
4. Add optioneel vercel.json voor framework-hints
5. Supabase side: hosted project moet bestaan (of nu upgraden van user's existing .env target). Migrations pushen via supabase db push --linked na project link
6. Deploy check: /login rendert, sign-in flow werkt tegen hosted Supabase

## Session in cijfers

2 tickets in 1 sessie, geen compactions. T-006 was substantial (correlated subquery RLS, versioning chain, 19 assertions). T-008 was HET grootste tot nu (4 tabellen, 21 assertions incl biconditional CHECK, bridge+map cross-tenant WRITE-block coverage). Multi-lens style code review met R2 revisions op T-006 en T-008 — beide converged in één R2 round.