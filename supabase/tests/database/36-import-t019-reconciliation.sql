BEGIN;
-- Depends on dim_pc seed rows: 111, 124, 200, 302 (see supabase/migrations/20260703020000_dim_pc.sql)
-- Depends on T-019 import migration 20260703160000_import_arbeidsduur_vakantiegeld_index_2024.sql

create extension if not exists pgtap;

select plan(17);

set local role service_role;


------------------------------------------------------------
-- Count invariants (3 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.param_arbeidsduur),
    4,
    'param_arbeidsduur has 4 rijen na T-019 import (PC 111, 124, 200, 302)'
);

select is(
    (select count(*)::int from public.param_vakantiegeld),
    2,
    'param_vakantiegeld has 2 rijen na T-019 import (arbeider + bediende)'
);

select is(
    (select count(*)::int from public.param_index),
    4,
    'param_index has 4 rijen na T-019 import (dezelfde 4 PCs als arbeidsduur)'
);


------------------------------------------------------------
-- Non-null bron_url invariants (3 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.param_arbeidsduur where bron_url is null),
    0,
    'param_arbeidsduur: geen NULL bron_url'
);

select is(
    (select count(*)::int from public.param_vakantiegeld where bron_url is null),
    0,
    'param_vakantiegeld: geen NULL bron_url'
);

select is(
    (select count(*)::int from public.param_index where bron_url is null),
    0,
    'param_index: geen NULL bron_url'
);


------------------------------------------------------------
-- Idempotency: lives_ok re-run + count-invariant (6 assertions)
------------------------------------------------------------

select lives_ok(
    $$
    insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url, bron_document)
    select v.pc_id, v.geldig_van, v.geldig_tot, v.gemiddelde_wekelijkse_uren, v.bron_url, v.bron_document
    from (values ('111'::text, '2024-01-01'::date, '2025-01-01'::date, 38.0000::numeric(6,4), 'x'::text, 'x'::text))
    as v(pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url, bron_document)
    where not exists (select 1 from public.param_arbeidsduur t where t.pc_id = v.pc_id and t.geldig_van = v.geldig_van)
    $$,
    'param_arbeidsduur idempotent re-run lives_ok (geen exclusion constraint fires)'
);

select lives_ok(
    $$
    insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url, bron_document)
    select v.regime, v.geldig_van, v.geldig_tot, v.enkel_pct, v.dubbel_pct, v.bron_url, v.bron_document
    from (values ('arbeider'::text, '2024-01-01'::date, '2025-01-01'::date, 0.1538::numeric(6,4), 0.0000::numeric(6,4), 'x'::text, 'x'::text))
    as v(regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url, bron_document)
    where not exists (select 1 from public.param_vakantiegeld t where t.regime = v.regime and t.geldig_van = v.geldig_van)
    $$,
    'param_vakantiegeld idempotent re-run lives_ok'
);

select lives_ok(
    $$
    insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url, bron_document)
    select v.pc_id, v.geldig_van, v.geldig_tot, v.index_coefficient, v.drempel_bruto, v.bron_url, v.bron_document
    from (values ('111'::text, '2024-01-01'::date, '2025-01-01'::date, 1.020000::numeric(10,6), 4000.0000::numeric(18,4), 'x'::text, 'x'::text))
    as v(pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url, bron_document)
    where not exists (select 1 from public.param_index t where t.pc_id = v.pc_id and t.geldig_van = v.geldig_van)
    $$,
    'param_index idempotent re-run lives_ok'
);

select is(
    (select count(*)::int from public.param_arbeidsduur),
    4,
    'param_arbeidsduur count unchanged (4) na idempotent re-run'
);

select is(
    (select count(*)::int from public.param_vakantiegeld),
    2,
    'param_vakantiegeld count unchanged (2) na idempotent re-run'
);

select is(
    (select count(*)::int from public.param_index),
    4,
    'param_index count unchanged (4) na idempotent re-run'
);


------------------------------------------------------------
-- Value spot-checks (4 assertions — dubbele coverage voor outlier PC 124)
------------------------------------------------------------

select is(
    (select gemiddelde_wekelijkse_uren from public.param_arbeidsduur where pc_id = '124'),
    40.0000::numeric(6,4),
    'PC 124 bouw heeft 40 u/week (uitzondering vs default 38)'
);

select is(
    (select index_coefficient from public.param_index where pc_id = '124'),
    1.015000::numeric(10,6),
    'PC 124 bouw heeft index_coefficient 1.015000 (outlier vs modale 1.020)'
);

select is(
    (select dubbel_pct from public.param_vakantiegeld where regime = 'arbeider'),
    0.0000::numeric(6,4),
    'arbeider dubbel_pct = 0.0000 (vakantiekas dekt zowel enkel als dubbel — biconditional cross-check documented rationale)'
);

select is(
    (select index_coefficient from public.param_index where pc_id = '111'),
    1.020000::numeric(10,6),
    'PC 111 metaal heeft index_coefficient 1.020000 (modale 2% indexatie)'
);


------------------------------------------------------------
-- Cross-cutting: POC_UNVERIFIED_2024 prefix in bron_document (1 assertion)
------------------------------------------------------------

select is(
    (select
        (select count(*) from public.param_arbeidsduur where bron_document like '[POC_UNVERIFIED_2024]%')
      + (select count(*) from public.param_vakantiegeld where bron_document like '[POC_UNVERIFIED_2024]%')
      + (select count(*) from public.param_index where bron_document like '[POC_UNVERIFIED_2024]%')
    )::int,
    10,
    'alle 10 T-019 rijen hebben [POC_UNVERIFIED_2024] prefix in bron_document (pre-productie deploy-gate)'
);


reset role;


select * from finish();
ROLLBACK;
