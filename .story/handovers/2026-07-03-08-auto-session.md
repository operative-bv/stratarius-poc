# Handover — T-009 klaar; Phase 2 Ruggengraat COMPLETE (6/6)

**Session**: bd773ebb (targeted auto, 1 ticket)
**Commit**: b075b73

## Wat is er gebeurd

**T-009** — 4 named views over bridge_hierarchie. Voor elke canonieke flavor (statutair, business, geografisch, kostenplaats) een view met dim_org_unit context (ancestor_name/kind, descendant_name/kind) joined. Alle 4 expliciet WITH (security_invoker = true) voor defense-in-depth. 11 pgTAP assertions incl cross-flavor negatives en RLS-erving check.

## Phase 2 Ruggengraat 6/6 COMPLETE 

✅ T-004 (dim_persoon + dim_functie) — 7047697
✅ T-005 (dim_land + dim_legale_entiteit) — 79bbc30
✅ T-006 (dim_contract) — 2675edb
✅ T-007 (dim_pc) — 4bef52a
✅ T-008 (org_unit + hiërarchie + bridge + map) — 7410c17
✅ T-009 (named views) — b075b73

Plus: T-039/T-040 (personal accounts + billing hide), ISS-012 fix, env var refactor (c706e8e). Phase 1 Foundation (5/5) + Phase 2 Ruggengraat (6/6) = 11 tickets domain-schema + 5 foundation = 16 committed migrations/tests.

## Vercel status

Terwijl deze auto-sessie draaide is de user Vercel aan het configureren. Verwacht workflow:
1. Project geimporteerd op Vercel dashboard
2. .env.vercel geupload (4 vars met new Supabase naming publishable_key/secret_key)
3. Deploy running
4. Post-deploy: `supabase db push` naar hosted project zodat 11 nieuwe migrations live komen

## Volgende stappen

Phase 3 (Componenten & SZ) is fully unblocked — 5 tickets:
- T-010 dim_sz_behandeling + seed 5 SZ-regimes
- T-011 dim_looncomponent schema + gedragstags
- T-012 dim_looncomponent seed + VAA-valkuil test (blocked op T-011)
- T-013 dim_prestatiecode + gedragstags + seed
- T-014 dim_scenario reference table

**Recommended volgende sessie**: `/story auto T-010 T-011 T-013 T-014` — alle unblocked Phase 3 tickets. T-012 volgt daarna (blocked op T-011).

Alternatief: `/story auto T-010 T-014` klein starten, dan T-011 + T-012 als pair (schema + seed).

**Bij Phase 4 (parameter-layer)** wordt Constitution Principe V TDD verplicht — dan speckit-flow (specify/plan/tasks/implement) i.p.v. storybloq auto. Phase 3 is nog schema-migrations, dus storybloq auto blijft prima.

## Session cijfers

T-009 was klein (5m verwacht), views + join tests. Phase 2 totaal: 6 tickets in 4 sessies (~1h20m aggregated) met multi-lens reviews per ticket.