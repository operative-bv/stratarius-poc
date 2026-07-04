BEGIN;
-- T-041 HOTFIX: param_rsz.basisfactor_pct wordt NOT NULL,
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

create extension if not exists pgtap;

select plan(3);


------------------------------------------------------------
-- S1: NOT NULL constraint aanwezig na HOTFIX
------------------------------------------------------------

select col_not_null(
    'public', 'param_rsz', 'basisfactor_pct',
    'S1 HOTFIX: param_rsz.basisfactor_pct is NOT NULL na HOTFIX'
);


------------------------------------------------------------
-- S2: bediende cat 1 backfill correct van null naar 1.0000
------------------------------------------------------------

select results_eq(
    $sql$
        select basisfactor_pct
        from public.param_rsz
        where status = 'bediende'
          and werkgeverscategorie = 1
          and geldig_van = '2024-01-01'::date
    $sql$,
    $sql$ values (1.0000::numeric(6,4)) $sql$,
    'S2 HOTFIX backfill: bediende cat 1 heeft basisfactor 1.0000 (was null)'
);


------------------------------------------------------------
-- S3: geen bediende rows meer met NULL basisfactor
--     (fold code-review error-handling MAJOR: verifieer volledigheid backfill
--     over cat 2/3 en toekomstige seeds, niet alleen cat 1 spot-check.)
------------------------------------------------------------

select results_eq(
    $sql$
        select count(*)::int
        from public.param_rsz
        where status = 'bediende'
          and basisfactor_pct is null
    $sql$,
    $sql$ values (0) $sql$,
    'S3 HOTFIX volledigheid: 0 bediende rows met NULL basisfactor (alle cat 1/2/3 gebackfilt)'
);


select * from finish();
ROLLBACK;
