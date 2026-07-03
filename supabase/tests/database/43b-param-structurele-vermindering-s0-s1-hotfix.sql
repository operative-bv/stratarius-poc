BEGIN;
-- T-042 HOTFIX: param_structurele_vermindering krijgt drempel_s0 en drempel_s1
-- numeric(18,4) NOT NULL kolommen met CHECK (drempel_s0 <= drempel_s1).
-- Backfill 2024 waardes: S0=7207.20, S1=12435.31 (bron: socialsecurity.be).

create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(3);

select col_not_null(
    'public', 'param_structurele_vermindering', 'drempel_s0',
    'S1 HOTFIX: drempel_s0 NOT NULL'
);

select col_not_null(
    'public', 'param_structurele_vermindering', 'drempel_s1',
    'S2 HOTFIX: drempel_s1 NOT NULL'
);

select results_eq(
    $sql$
        select drempel_s0, drempel_s1
        from public.param_structurele_vermindering
        where werkgeverscategorie = 1
          and geldig_van = '2024-01-01'::date
    $sql$,
    $sql$ values (7207.2000::numeric(18,4), 12435.3100::numeric(18,4)) $sql$,
    'S3 HOTFIX backfill: cat 1 2024 heeft S0=7207.20 en S1=12435.31'
);

select * from finish();
ROLLBACK;
