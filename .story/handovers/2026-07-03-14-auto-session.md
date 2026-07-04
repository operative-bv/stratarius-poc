# Autonomous Session Handover — T-018 (First import-ticket)

## Delivered

**T-018 — Import 2024 RSZ + structurele + doelgroepvermindering baseline** (commits `cb550ad`, `95014f6`)

Eerste **non-migration** ticket in de POC — vult 3 parameter-tabellen met concrete 2024 tarieven:

- **param_rsz** (6 rijen): 25.07% / 24.32% / 17.07% basisbijdrage per werkgeverscategorie 1/2/3. Arbeider-rijen krijgen 108% basisfactor per PDF Laag 3.
- **param_structurele_vermindering** (3 rijen): formule R = F - a·(S₀-S) - b·(S₁-S). Cat 1 (algemeen/privé) enkel coefficient_a=0.14; cat 2 (social profit) forfait €49 + coefficient; cat 3 (beschutte werkplaats) forfait €375 + dubbele coefficient.
- **param_doelgroepvermindering** (6 rijen): 2 doelgroepen per gewest × 3 gewesten = 6. VDAB Vlaanderen (oudere 60+ €600, jongere_zonder_diploma €1000), Forem Wallonie (Impulsion jongere + langdurig €500 each), Actiris Brussel (Activa 55+ €1000, langdurig werkloos €350). Voorwaarden in jsonb.

**Nieuwe patterns vs migration-tickets:**
- Multi-row VALUES + WHERE NOT EXISTS per tabel (3 statements ipv 15 individuele INSERTs).
- Idempotent via business-key deduplication; verified `INSERT 0 0` op re-run.
- **Machine-readable safety marker**: elke `bron_document` prefix `[POC_UNVERIFIED_2024]`. Pre-productie gate-query kan detecteren of POC-seed nog aanwezig is en deploy blokkeren.

**pgTAP `plan(18)`**: count invariants × 3, non-null bron_url × 3, idempotency (lives_ok re-run × 3 + count-invariant × 3), value spot-checks × 4 (arbeider factor 1.08, bediende basisbijdrage 24.32%, structurele cat 3 forfait 375, Brussel activa_50plus min_leeftijd 55 in jsonb), biconditional cross-check × 2.

Manual psql smoke: 6+3+6=15 rijen ge-import, values correct, re-run idempotent. `npm run build` exit 0.

## Beslissingen genomen

**Plan review (2 rondes)**
- R1: revise (5 findings). Alle 5 gefold: CC1 15→3 INSERT-blocks via multi-row VALUES; SS1 POC_UNVERIFIED_2024 prefix; SS2 concurrency tradeoff (WHERE NOT EXISTS niet strict concurrent-safe, acceptabel voor Supabase migration runner); EE1 lives_ok rond re-run; EE2 EE4 heruitgetrokken naar concrete follow-up ISS-032. plan(15) → plan(18).
- R2: approve (0 findings).

**Code review (1 ronde, lenses)**
- 1 suggestion (test-atomicity idempotency + count niet gekoppeld). Contested — count-invariant assertions vangen row-count wijziging. Verdict approve.

**Belangrijkste scope-beslissing: EE4 heruitgetrokken naar ISS-032**
T-015/T-016 code-review had value-range CHECK constraints (bv `basisbijdrage_pct BETWEEN 0 AND 1`) gedeferred naar T-018. Bij T-018 plan-review is besloten scope-scheiding aan te houden: T-018 blijft puur data-import; schema-side CHECK-uitbreiding krijgt eigen ticket via **ISS-032** (11 constraints across parameter layer). Dit voorkomt dubbele scope in T-018.

**Data-accuraatheid**: waarden zijn plausibele orde-van-grootte voor 2024, niet 100% verified. POC_UNVERIFIED_2024 prefix + top-of-file banner in migration comment maakt dit expliciet.

**Format**: SQL migration ipv TypeScript script. Voor 15 rijen POC-scope is dit simpler. TypeScript komt later terug voor bron-fetching pipelines (grotere volumes, dry-run, edge functions).

## Pre-existing issues gefiled

- **ISS-032** (medium): Add value-range CHECK constraints across parameter layer. Concrete voorstel voor 11 constraints (basisbijdrage_pct, basisfactor, forfait, coefficients, tarief, taks_pct, index_coefficient, vaa_coefficient, gemiddelde_wekelijkse_uren). Related tickets T-015/T-016/T-017/T-018.

## Status van de POC

**Phase 4 parameterlaag (schema + data 2024): COMPLEET**

- T-012 dim_looncomponent seed (12 canonieke loonvormen)
- T-015 param_rsz + param_plafond schema
- T-016 param_structurele + param_doelgroep schema
- T-017 7 param_* tabellen schema afronding
- T-018 concrete 2024 baseline import

**11 parameter-tabellen** live met CHECK-constraints, RLS role-scoped, exclusion op tijdvakken. **15 rijen** concrete data voor 2024 (3 tabellen). Rekencascade heeft nu alles wat nodig is qua parameter-data.

## Volgende stap voor de gebruiker

1. `git push` — 3 commits ahead (cb550ad, 95014f6).
2. `supabase db push` naar hosted Supabase voor T-018 migration.
3. **Vanaf T-022** (fact tables): overweeg switch naar speckit-flow (Phase 5 calculation-cascade start).
4. Alternatief: T-019 en T-020 zijn nog niet-import ticket voor de andere parameter tabellen (arbeidsduur, vakantiegeld, index, bijzondere_bijdragen, sectorbijdrage, extralegaal, wagen_mobiliteit) — blijft Phase 4 en Storybloq flow.
5. ISS-032 kan opgepakt worden als aparte value-range CHECK migration (medium priority).

## Session eind status

Session `13eda08a-91fc-4f83-80ac-a558fa281743` targeted work complete. 1/1 target: T-018 delivered in 2 commits + 2 plan-review + 1 code-review rondes + 1 issue gefiled. Branch `main` clean. **Goed pauzemoment** voor de gebruiker om naar huis te fietsen 🚀.
