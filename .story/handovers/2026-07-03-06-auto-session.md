# Handover — T-005 done, Phase 2 Ruggengraat 3/6

**Session**: 215d6b2e (targeted auto, 1 ticket)
**Commit**: 79bbc30
**Branch**: main

## Wat is er gebeurd

**T-005** — dim_land + dim_legale_entiteit met team-only tenant RLS. Twee tabellen in één migration + 20 pgTAP assertions.

Belangrijke design keuzes:
- `basejump_account_id` (niet generic `owning_account_id` zoals T-004) — expliciete naming omdat de tenant IS een Basejump team-account. N-007 enforcement is Basejump-specifiek.
- Team-only enforcement via `SECURITY DEFINER` trigger die basejump.accounts checkt — CHECK constraints kunnen geen cross-table refs, dus trigger. Search_path pinned voor security.
- Trigger RAISE met SQLSTATE 23514 (check_violation) voor deterministic pgTAP throws_ok match.
- dim_land uppercase-only via CHECK; ondernemingsnr regex is BE-only (`land_id <> 'BE' OR regex`).

## Pre-existing houseckeeping

ISS-012 gefixt vlak voor deze sessie: T-004 test had dezelfde broken cmp_ok(updated_at > created_at) assertion. Verwijderd (plan(16)→plan(15)) met inline note referencing ISS-012. Aparte commit `3c2578d`.

## Reviewer inzichten deze sessie

Round 1 code review vond echte issues:
- **F3 (medium)**: trigger function had geen SECURITY DEFINER — kon tenant met beperkte GRANT op basejump.accounts silently accepting personal-account FK. Gefixt met security definer + set search_path.
- **F5 (low)**: `set local role postgres` niet portable naar non-superuser CI. Vervangen door `reset role`.
- **F1 (high)**: plan(20) mismatch — gecontesteerd via grep, telling van 20 assertions confirmed. Reviewer miscount.

Round 2 code review approve, no findings.

## Codex situatie

Storybloq rond 2 vraagt om codex backend; auto-mode classifier blijft blokkeren wegens source-exfil concern. Fallback naar agent per guide's instructie werkt prima maar user's wens "beide backends per round" vereist expliciete permission-rule in `.claude/settings.local.json`:
```json
"Bash(codex exec:*)",
"Bash(codex --version)",
"Bash(git diff * | codex exec:*)"
```
Auto-mode blokkeert self-modification van settings, dus user moet handmatig aanpassen.

## Volgende stappen

Phase 2 Ruggengraat 3/6:
- ✅ T-004, T-005, T-007
- ⏬ T-006 `dim_contract` — nu unblocked (was blocked op T-004, T-005, T-007 — alle drie klaar)
- ⏬ T-008 `dim_org_unit + hierarchie + map_entiteit_pc_competentie` — nu unblocked (was blocked op T-005 en T-007)
- ⏬ T-009 `named hierarchy views` — blocked op T-008

**Kritisch pad**: T-006 zit op de meeste dependency chains verder (rekencascade Phase 5 depends op fact_* die op dim_contract wachten). T-008 verplaatst hiërarchie forward.

**Recommended next**: `/story auto T-006` — belangrijkste enkelvoudige ticket. Of `/story auto T-006 T-008` — sluit Ruggengraat bijna af (T-009 volgt).

Phase 3 (schema-componenten) kop T-010 dim_sz_behandeling zit ook al vrij (blocked op T-005 only). Kan parallel met T-006/T-008.

## Sessions in cijfers

T-005 was substantial ticket: 2 tables, 20 assertions, 6 review findings (3 addressed, 2 contested/deferred). ~15 min effectief werk in de state machine — Ruggengraat schema-migrations lopen betrouwbaar in 10-20 min per ticket.