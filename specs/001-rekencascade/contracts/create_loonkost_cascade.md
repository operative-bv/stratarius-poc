# Contract: `create_loonkost_cascade`

**Status**: proposed | **Owner ticket**: T-027 (orchestrator step; assumes T-023-T-028 stapfuncties bestaan)

## Signature

```sql
create or replace function public.create_loonkost_cascade(
    p_contract_id uuid,
    p_periode date,
    p_scenario_id uuid,
    p_snapshot_batch_id uuid
) returns table (
    kostenblok text,
    bedrag numeric(18,4)
)
    language plpgsql
    security definer
    set search_path = pg_catalog, pg_temp
as $$
    -- Body: valideert inputs, delegateert naar 9 stap-functies (T-026/T-027/T-028),
    -- schrijft resultaat naar fact_loonkost via canonieke INSERT ... ON CONFLICT
    -- (contract_id, periode, kostenblok, scenario_id) DO UPDATE, returnt de 7 rijen.
$$;

revoke execute on function public.create_loonkost_cascade(uuid, date, uuid, uuid) from public, authenticated, anon;
grant execute on function public.create_loonkost_cascade(uuid, date, uuid, uuid) to service_role;
```

## Preconditions

- `p_contract_id` bestaat in `dim_contract` en caller heeft basejump-role op de bijhorende `legale_entiteit_id`.
- `p_periode` voldoet `date_trunc('month', p_periode) = p_periode`. Anders → `raise exception 'invalid periode: must be month-begin'`.
- `p_scenario_id` bestaat in `dim_scenario` en verwijst naar hetzelfde `legale_entiteit_id` als het contract.
- `p_snapshot_batch_id` bestaat in `audit_parameter_snapshot`.
- Voor elke parameterlaag-tabel die de cascade nodig heeft: er is minstens één actieve rij voor `p_periode` (`p_periode >= geldig_van AND (geldig_tot IS NULL OR p_periode < geldig_tot)`). Anders → `raise exception 'missing param row: <tabel> for periode <p>'`.

## Postconditions

- Er zijn exact 7 rijen in `fact_loonkost` voor `(p_contract_id, p_periode, kostenblok, p_scenario_id)` — één per canonieke kostenblok (Decision 4).
- Elke rij heeft `snapshot_batch_id = p_snapshot_batch_id` en `cascade_run_at = now()`.
- Return-set komt overeen met de 7 nieuwe/geüpdate rijen (kostenblok, bedrag).
- Alle bedragen zijn afgerond door `round_final()` (T-025) op 2 decimalen output-precisie.

## Deterministiek contract (Constitution Principe III MUST regel 127)

Voor identieke input `(p_contract_id, p_periode, p_scenario_id, p_snapshot_batch_id)` en identieke fact_looncomponent/fact_prestatie/fact_wagen state, **MOET** deze function byte-identical return-set produceren over onbeperkt aantal invocations, zelfs na parameter-updates in `param_*` tabellen (want de temporele join tegen snapshot filtert die uit).

⚠️ De function raadpleegt live `param_*` tabellen, niet historische snapshots. Reproduceerbaarheid vereist dat `param_*` rijen relevante for `p_periode` niet retroactief wijzigen (Constitution Principe I MUST — geen UPDATE buiten typo-fix). Als een parameter-rij tussentijds vervangen wordt, is de historische cascade niet meer 1-op-1 reproducerbaar; alleen `snapshot_batch_id` wijst dan naar het historische bewijs.

## Foutmodes

- `raise exception 'invalid periode: must be month-begin, got %', p_periode` — periode is niet maand-begin.
- `raise exception 'contract % not found or access denied', p_contract_id` — contract bestaat niet of tenant-scope faalt.
- `raise exception 'scenario % does not belong to contract legale_entiteit', p_scenario_id` — scenario is voor andere entity.
- `raise exception 'snapshot_batch % not found in audit_parameter_snapshot', p_snapshot_batch_id`.
- `raise exception 'missing param row: % for periode %', tabel_naam, p_periode` — parameterlaag-hiaat.
- `raise exception 'missing fact: % for contract % periode %', fact_type, p_contract_id, p_periode` — geen input-facts.

## Testbaarheid (Principe V)

pgTAP tests EERST (Red):
- lives_ok voor bekend refscenario (bediende cat 1, PC 200, brutoloon €4.000) — verify 7 rijen return + specifieke bedragen matchen handmatige berekening binnen €0.01.
- throws_ok voor invalid periode ('2024-03-15') → 'invalid periode' exception.
- throws_ok voor tenant-mismatch (contract van andere account) → 'access denied'.
- throws_ok voor invalid snapshot_batch_id → 'not found'.
- **Idempotency**: 2 opeenvolgende calls met identieke inputs → identieke return-set.
- **Determinisme**: 10 opeenvolgende calls in verschillende volgorde met identieke inputs → alle 10 identiek.
