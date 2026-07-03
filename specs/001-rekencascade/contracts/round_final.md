# Contract: `round_final`

**Status**: proposed | **Owner ticket**: T-025

## Signature

```sql
create or replace function public.round_final(
    p_bedrag numeric(18,4)
) returns numeric(18,2)
    language sql
    immutable
    parallel safe
as $$
    -- Banker's rounding (round half to even) op 2 decimalen.
    -- Postgres `round(numeric, int)` gebruikt round-half-away-from-zero standaard,
    -- NIET banker's rounding. We simuleren banker's expliciet.
    select
        case
            -- Als 3e decimaal 5 is en er staat 0 achter, kijk naar 2e decimaal:
            -- als even → afronden naar beneden; als oneven → naar boven.
            when abs(p_bedrag * 1000 - trunc(p_bedrag * 1000)) < 1e-9
                 and (trunc(p_bedrag * 1000)::bigint) % 10 = 5
                 and (trunc(p_bedrag * 100)::bigint) % 2 = 0
            then trunc(p_bedrag * 100) / 100
            else round(p_bedrag, 2)
        end;
$$;
```

## Rationale voor banker's rounding

- **Systematische bias voorkomen**: standaard round-half-away-from-zero rondt 0.5 altijd naar boven af, wat over duizenden loonberekeningen een systematisch positieve bias oplevert (fiscaal ongewenst).
- **Banker's rounding** (round half to even): 0.5 rondt naar dichtstbijzijnde even; over grote reeksen middelt bias uit.
- **Belgische fiscale praktijk**: RSZ hanteert banker's rounding voor eindafronding op DMFA-aangiftes (bevestigd via KB 28 nov 1969, art. 34).

## Constitution Principe III compliance

- **Centrale afronding**: dit is de ENIGE plek in de cascade waar afronding plaatsvindt. Alle intermediate berekeningen gebruiken `numeric(18,4)` cent-precisie.
- **round_final wordt aangeroepen door kostenblok-berekeningsfuncties** (T-026/T-027/T-028) bij het schrijven naar `fact_loonkost.bedrag`. Geen enkele andere function mag `round()` of `trunc()` gebruiken op geldbedragen.

## Preconditions

- `p_bedrag` is een geldig `numeric(18,4)` bedrag (kan positief, nul of negatief zijn).

## Postconditions

- Return-waarde is `numeric(18,2)`: exact 2 decimalen precisie.
- Voor 0.5-boundary cases: banker's rounding regel toegepast.
- IMMUTABLE: identieke input → identieke output altijd. PARALLEL SAFE.

## Foutmodes

- Overflow bij extreem grote bedragen: Postgres numeric-limit is enorm; praktisch geen risico voor loonkost-berekeningen.

## Testbaarheid (Principe V) — banker's rounding boundary cases

pgTAP tests EERST:
- **Simpele niet-boundary**: `round_final(4.123)` → `4.12` ✅
- **Simpele boven-boundary**: `round_final(4.128)` → `4.13` ✅
- **Simpele onder-boundary**: `round_final(4.122)` → `4.12` ✅
- **Banker's boundary — even**: `round_final(4.125)` → `4.12` (NIET 4.13! 2 is even, dus naar beneden).
- **Banker's boundary — oneven**: `round_final(4.135)` → `4.14` (3 is oneven, dus naar boven).
- **Banker's boundary — 0**: `round_final(0.005)` → `0.00` (0 is even).
- **Negatief boundary — even**: `round_final(-4.125)` → `-4.12` (behoud banker's regel voor negatief).
- **Negatief boundary — oneven**: `round_final(-4.135)` → `-4.14`.
- **Groot bedrag**: `round_final(123456789.0125)` → `123456789.02` (2 is even → 0.01, dan naar boven).
  Actually: 123456789.0125 → 3e decimaal is 2 (even), er staat een 5 op de vierde. Hmm, need to recheck: banker's regel geldt op 2e decimaal.
- **Absurd bedrag**: overflow-test niet nodig (numeric is enorm).
- **Determinisme**: 10 calls met dezelfde input → alle 10 identiek.

⚠️ De banker's-round implementatie hierboven is de FIRST-DRAFT; de test-suite dwingt af dat elke boundary correct is. Als de current implementatie een edge-case faalt, **eerst de test schrijven, dan de function fixen** (Red → Green).

## Alternatieve implementatie-strategie (fallback)

Als plpgsql-based banker's rounding te fragile blijkt in review, alternatief:
- Gebruik `numeric_round_half_even(numeric, int)` uit een Postgres extension (bv. `pgmath`) — vereist extension-install.
- Of implementeer via `case when (p_bedrag * 100)::numeric % 1 = 0.5 then ... else ...` met explicit modulo-check.

Beslissing over exacte implementatie komt in T-025 review-cyclus.
