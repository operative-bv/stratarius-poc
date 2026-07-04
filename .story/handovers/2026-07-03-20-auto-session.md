# Autonomous Session Handover — T-025 (round_final centrale afronding)

## Delivered

**T-025** (commits `73cd55b` Red, `9b69ee3` Green, `77a283d` metadata)

Vierde Phase 5 ticket. Centrale afrondingsfunctie als ENIGE plek waar bedragen in Stratarius afgerond worden (Constitution Domain sectie). Purpose-gedreven dispatcher naar banker's (DMFA-conform) of half-away-from-zero (commercial rounding).

### Function

```sql
public.round_final(p_bedrag numeric, p_purpose text default 'display')
  returns numeric(18, 2)
  language plpgsql immutable parallel safe
```

Private helpers (REVOKE from public, geen tenant-toegang):
- `_round_banker_2(numeric)` — banker's rounding (round half to even)
- `_round_half_up_2(numeric)` — wrapper op Postgres round() (half-away-from-zero)

**Semantiek**:
| purpose | methode | use case |
|---|---|---|
| display, report | banker's | UI, DMFA, loonstrook (KB 28/11/1969 art. 34) |
| export, invoice | half-up | CSV bulk-export, factuur naar tenant |
| onbekend | RAISE SQLSTATE 22023 | fail-loud, geen silent NULL |

### Verified alle 15 scenarios (manual + docker psql)

- T3-T7 banker's positief (4.125→4.12 even, 4.135→4.14 oneven, 0.005→0.00 nul) ✅
- T8-T9 banker's negatief (Postgres modulo sign semantics) ✅
- T10-T12 half-up divergentie (0.005 export→0.01 vs banker's 0.00) ✅
- T13 purpose divergentie bewijs ✅
- T14 unknown purpose raist SQLSTATE 22023 met exact-string message ✅
- T14b NULL bedrag → NULL (documented) ✅
- T14c unbounded param preservation (4.1250001→4.13) ✅
- T15b pg_proc.provolatile = 'i' ✅
- Privilege scope: authenticated CAN round_final, CANNOT helpers ✅

pgTAP plan(18) lokaal geblokt door ISS-030 (basejump-supabase_test_helpers extension missing). Handmatige verificatie via docker exec psql.

## Beslissingen genomen — 4 folds uit plan-review round 1

**Plan-review**: 3 lenses (clean-code, security, error-handling) convergeerden op silent-NULL risk. 4 majors + 4 minors gefold in plan v2 vóór implementation.

1. **LANGUAGE plpgsql + RAISE EXCEPTION** (was: SQL + else null)
   - Origineel plan had `else null` — 3 lenses zeiden: silent NULL propageert door loonstroken zonder alarm.
   - Fold: plpgsql pure functie is ook IMMUTABLE + PARALLEL SAFE — geen optimizer verlies.
   - RAISE met SQLSTATE 22023 (invalid_parameter_value) is machine-readable, message bevat exacte purpose-waarde.

2. **Unbounded `p_bedrag numeric`** (was: `numeric(18,4)`)
   - Error-handling lens: caller met >4-decimal precisie zou impliciete PG-cast met round-half-away-from-zero ondergaan Vóór banker's kan toegepast worden.
   - Voorbeeld: 4.1250001 → cast naar (18,4) → 4.1250 → spurious banker's boundary. Nu blijft 4.1250001 exact, valt in niet-boundary branch, geeft 4.13.
   - Bewijs via T14c.

3. **REVOKE EXECUTE op helpers** (was: GRANT EXECUTE op alles)
   - Security lens: `_round_banker_2` naming (`_prefix`) signaleert intern, maar plan gaf execute-recht aan authenticated.
   - Fold: REVOKE on both helpers, GRANT alleen op dispatcher. Elke banker's-call moet door dispatcher met bewuste purpose-keuze — audit-spoor in call-site.
   - Verified via `has_function_privilege(authenticated, ...)`.

4. **Symmetric `_round_half_up_2` helper** (was: inline `round(p_bedrag, 2)` in dispatcher)
   - Clean-code lens: dispatcher CASE duplicated banker's/half-up branches.
   - Fold: aparte helper voor symmetrie. Toevoegen van 5e purpose = 1 dispatcher-regel, geen wijziging aan methode-logica.

**Bonus folds** (minor findings uit plan-review):
- T15 split naar T15a (determinisme) + T15b (pg_proc.provolatile check)
- T14b NULL bedrag test toegevoegd (distinct van unknown purpose signal)
- Rollback commands gedocumenteerd in migration header comment
- DoD krijgt has_function_privilege check + lightweight git grep

**Contested finding** (niet gefold):
- Clean-code suggestion: purpose vs mode naming — ticket-authored contract expliciet purpose enum (display|report|export|invoice). User intent > lens preference.

**Code-review**: 0 findings uit 3 lenses. Clean approve.

## Inline fixes tijdens implementation

1. Broken eerste `create or replace round_final` met `case ... else null end + exception when others then raise` — semantisch bug: NULL werd voor RAISE geretourneerd. Verwijderd, alleen if-elsif-else versie behouden.
2. plpgsql `RAISE ... '%L' ...` — %L is format() syntax, geen RAISE-syntax. Gecorrigeerd naar plain `'...''%''...'` (letterlijke enkele quotes rond purpose in message).

## Pre-existing issues gefiled

- **ISS-035** (medium): CI grep-based lint dat verifieert `round_final` is de ENIGE afrondingsplek in codebase. Zonder deze hook is Principe III "single rounding location" een documentatie-claim, geen invariant.
- **ISS-036** (medium): TypeScript parallel implementatie voor Phase 7 UI-simulator. Byte-voor-byte identieke boundary uitkomst vereist als SQL versie — anders divergeren UI-preview en persisted amounts op 0.5-boundaries.

## Volgende stap

1. `git push` — 3 commits ahead (73cd55b, 9b69ee3, 77a283d).
2. `supabase db push` naar hosted.
3. **T-026** — volgende Phase 5 ticket: cascade-stap 1 (bruto → RSZ-grondslag berekening). Speckit-plan zou beginnen te lopen per feedback-phase-flow-choice memory (T-026+ = speckit-flow, NIET Storybloq auto).

## Session eind status

Session `f82c7daf-1d42-48ea-84f3-7d94838dee8c` complete. 1/1 target: T-025 delivered in 3 commits + 1 plan-review round (4 major folds) + 1 code-review round (0 findings) + 2 issues gefiled + 2 inline fixes. Branch `main` clean. Phase 5 speckit+Storybloq vierde validatie. Constitution Principe III (single rounding location) is nu daadwerkelijk geinstantieerd.