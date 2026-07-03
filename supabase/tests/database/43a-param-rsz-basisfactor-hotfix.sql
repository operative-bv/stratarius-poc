BEGIN;
-- T-041 HOTFIX: param_rsz.basisfactor_arbeider_pct wordt NOT NULL,
-- bediende rows worden gebackfilt van null naar 1.0000, conditional CHECK verwijderd.
--
-- Principe V (test-first): dit test-bestand wordt gecommit vóór de HOTFIX migration.
-- Bij eerste run zonder migration: col_not_null faalt → Red.
--
-- Rationale fold uit T-026 plan-review (2026-07-03):
--   Origineel schema had conditional CHECK ((status='bediende' and factor is null)
--   or (status='arbeider' and factor is not null)) waardoor cascade functie moest
--   coalescen (Principe II inbreuk: branching op status in code). Nieuwe schema:
--   alle rows hebben factor NOT NULL (bediende = 1.0000 by-convention, arbeider = 1.0800).

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(2);


------------------------------------------------------------
-- S1: NOT NULL constraint aanwezig na HOTFIX
------------------------------------------------------------

select col_not_null(
    'public', 'param_rsz', 'basisfactor_arbeider_pct',
    'S1 HOTFIX: param_rsz.basisfactor_arbeider_pct is NOT NULL na HOTFIX'
);


------------------------------------------------------------
-- S2: bediende cat 1 backfill correct van null naar 1.0000
------------------------------------------------------------

select results_eq(
    $sql$
        select basisfactor_arbeider_pct
        from public.param_rsz
        where status = 'bediende'
          and werkgeverscategorie = 1
          and geldig_van = '2024-01-01'::date
    $sql$,
    $sql$ values (1.0000::numeric(6,4)) $sql$,
    'S2 HOTFIX backfill: bediende cat 1 heeft basisfactor 1.0000 (was null)'
);


select * from finish();
ROLLBACK;
