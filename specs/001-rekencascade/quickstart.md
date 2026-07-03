# Quickstart: Rekencascade lokaal testen

**Date**: 2026-07-03
**Audience**: ontwikkelaars die de cascade lokaal willen valideren tijdens Phase 5 implementatie.

Deze guide beschrijft de minimale stappen om een cascade-run lokaal te reproduceren nadat T-022 t/m T-029 volledig geïmplementeerd zijn. Voor deze eerste slice (T-022 alleen) beperkt de quickstart zich tot fact-table validatie zonder cascade-execution.

## Prerequisites

- Docker draait (Supabase local dependency).
- Supabase CLI geïnstalleerd.
- Node.js 20+ voor `npm run build`.
- Repo op branch `001-rekencascade` (of `main` met T-022 migration gemerged).

## Stap 1 — Supabase local starten en migrations toepassen

```bash
supabase start
supabase db reset
```

Dit past alle migrations toe tot en met de laatste committed T-022 migration. Verwacht: `20260703200000_fact_tables.sql` staat in de output.

## Stap 2 — Fact-table smoke test (T-022 alleen)

```bash
# Verify de 4 fact tables bestaan
docker exec supabase_db_basejump-next psql -U postgres -c "\dt public.fact_*"

# Verwacht: fact_looncomponent, fact_prestatie, fact_wagen, fact_loonkost
```

**AFGELEID-invariant test op fact_loonkost**:

```bash
# Als authenticated user: INSERT MOET falen
docker exec supabase_db_basejump-next psql -U postgres -c "
SET LOCAL ROLE authenticated;
INSERT INTO public.fact_loonkost (contract_id, periode, kostenblok, scenario_id, bedrag, snapshot_batch_id)
    VALUES (gen_random_uuid(), '2024-01-01'::date, 'bruto', gen_random_uuid(), 100.00, gen_random_uuid());
"
# Verwacht: ERROR 42501 permission denied for table fact_loonkost
```

## Stap 3 — Seed test-data (voor cascade-runs vanaf T-023)

*Deze stap is pas relevant zodra T-023+ geïmplementeerd zijn.*

```bash
# Snapshot van huidige parameter-laag
docker exec supabase_db_basejump-next psql -U postgres -c "
SELECT public.create_parameter_snapshot('cascade-quickstart') AS batch_id;
"
# Note the returned batch_id — use it below

# Seed één test-contract (bediende, PC 200, brutoloon €4.000)
docker exec supabase_db_basejump-next psql -U postgres <<'SQL'
-- Seed dim_persoon
INSERT INTO public.dim_persoon (persoon_id, geslacht, geboortedatum)
    VALUES ('11111111-1111-1111-1111-111111111111', 'F', '1985-06-15');

-- Seed legale_entiteit (met account_id van je test-user)
-- ...

-- Seed dim_contract (bediende, PC 200)
INSERT INTO public.dim_contract (
    contract_id, persoon_id, legale_entiteit_id, pc_id, statuut,
    fte_breuk, geldig_van, geldig_tot
) VALUES (
    '22222222-2222-2222-2222-222222222222',
    '11111111-1111-1111-1111-111111111111',
    -- legale_entiteit_id
    '200', 'bediende', 1.0, '2024-01-01', NULL
);

-- Seed fact_looncomponent voor basisloon €4.000 in maart 2024
INSERT INTO public.fact_looncomponent (
    contract_id, periode, component_id, scenario_id, bedrag
) VALUES (
    '22222222-2222-2222-2222-222222222222',
    '2024-03-01',
    'basisloon',
    -- scenario_id
    4000.0000
);

-- Seed fact_prestatie voor 164u normale prestatie
INSERT INTO public.fact_prestatie (
    contract_id, periode, prestatiecode_id, uren, dagen
) VALUES (
    '22222222-2222-2222-2222-222222222222',
    '2024-03-01',
    'normale_uren',
    164.0000,
    21.0000
);
SQL
```

## Stap 4 — Cascade uitvoeren (vanaf T-027 orchestrator beschikbaar)

```bash
docker exec supabase_db_basejump-next psql -U postgres -c "
SELECT * FROM public.create_loonkost_cascade(
    '22222222-2222-2222-2222-222222222222'::uuid,
    '2024-03-01'::date,
    -- scenario_id
    -- batch_id (uit stap 3)
);
"
```

Verwacht: 7 rijen returned, één per canonieke kostenblok:

```
 kostenblok       | bedrag
------------------+----------
 bruto            | 4000.00
 werkgevers_rsz   |  ~1002.80  (25.07% × 4000)
 vakantiegeld     |   ~306.80  (7.67% × 4000)
 ejp              |     ~0.00  (nog niet toegepast in POC)
 extralegaal      |     ~0.00
 wagen_tco        |     ~0.00
 arbeidsongevallen|     ~40.00  (~1% × 4000, placeholder)
```

Exacte bedragen zullen afhangen van T-018 baseline en cascade-implementatie; validatie tegen handmatige berekening in T-029.

## Stap 5 — Idempotency & determinisme verifiëren

```bash
# Draai cascade twee keer met identieke inputs
docker exec supabase_db_basejump-next psql -U postgres -c "
SELECT public.create_loonkost_cascade(...) AS run1;
SELECT public.create_loonkost_cascade(...) AS run2;

-- Verifieer: 2e call heeft dezelfde output als 1e
SELECT COUNT(*) FROM fact_loonkost WHERE contract_id = '22222222-...' AND periode = '2024-03-01';
-- Verwacht: 7 (ON CONFLICT DO UPDATE — geen duplicaten)
"
```

## Stap 6 — pgTAP tests draaien

Wanneer ISS-030 (basejump-supabase_test_helpers extensie missing) opgelost is:

```bash
supabase test db
```

Verwacht: alle 40+ suites slagen inclusief nieuwe cascade-tests (39-cascade-fact-tables t/m 47-referentiescenarios).

Tot ISS-030 opgelost is: manual smoke via `docker exec psql` per test-scenario.

## Stap 7 — Build check

```bash
npm run build
```

Verwacht: exit 0. Cascade is puur database-side; Next.js bundle-size wijzigt niet.

## Troubleshooting

- **"missing param_rsz for periode 2024-03-01"**: parameter-laag import (T-018 t/m T-020) is niet gerund. Draai `supabase db reset` opnieuw.
- **"missing fact_prestatie"**: seed-data uit Stap 3 is niet toegepast.
- **"permission denied on fact_loonkost"**: verwacht bij authenticated role — dit is de AFGELEID-invariant die werkt. Gebruik service_role (via de function) om cascade uit te voeren.
- **Determinisme faalt tussen runs**: check of tussentijds een parameter-import gebeurd is die de temporele join beïnvloedt. Gebruik altijd hetzelfde `snapshot_batch_id`.

## Referentiescenarios (T-029)

Volledige RSZ-brochure referentiescenario suite draait via:
```bash
docker exec supabase_db_basejump-next psql -U postgres -f supabase/tests/database/47-referentiescenarios.sql
```

Elk profiel test één kostenblok-breakdown tegen handmatig-gecontroleerde verwachte bedragen binnen €0.01 tolerantie.
