BEGIN;
-- T-042 HOTFIX: param_structurele_vermindering krijgt drempel_s0 en drempel_s1
-- numeric(18,4) NOT NULL kolommen. Semantiek gewijzigd na fiscal audit
-- (20260703260000): coefficient_b repurposed als γ zeer-lage-lonen ipv δ hoog-lonen.
-- Waarde 2024 cat 1: S0=10797.67 (lage-lonen α drempel), S1=6807.18 (zeer-lage
-- γ drempel). Cross-checked easypay-group.com.

create extension if not exists pgtap;

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
    $sql$ values (10797.6700::numeric(18,4), 6807.1800::numeric(18,4)) $sql$,
    'S3 fiscal audit: cat 1 2024 heeft S0=10797.67 (α), S1=6807.18 (γ zeer-lage-lonen)'
);

select * from finish();
ROLLBACK;
