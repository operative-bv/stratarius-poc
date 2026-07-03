BEGIN;
create extension "basejump-supabase_test_helpers" version '0.0.6';

select plan(18);

set local role service_role;


------------------------------------------------------------
-- Count invariants (3 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.param_rsz),
    6,
    'param_rsz has 6 rijen na T-018 import (2 status x 3 werkgeverscategorie)'
);

select is(
    (select count(*)::int from public.param_structurele_vermindering),
    3,
    'param_structurele_vermindering has 3 rijen na T-018 import (3 werkgeverscategorie)'
);

select is(
    (select count(*)::int from public.param_doelgroepvermindering),
    6,
    'param_doelgroepvermindering has 6 rijen na T-018 import (2 doelgroepen x 3 gewesten)'
);


------------------------------------------------------------
-- Non-null bron_url invariants (3 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.param_rsz where bron_url is null),
    0,
    'param_rsz: geen NULL bron_url (spec-vereiste import)'
);

select is(
    (select count(*)::int from public.param_structurele_vermindering where bron_url is null),
    0,
    'param_structurele_vermindering: geen NULL bron_url'
);

select is(
    (select count(*)::int from public.param_doelgroepvermindering where bron_url is null),
    0,
    'param_doelgroepvermindering: geen NULL bron_url'
);


------------------------------------------------------------
-- Idempotency: re-run INSERTs, verify lives_ok + count unchanged (6 assertions)
------------------------------------------------------------

-- Re-run param_rsz insert — bewijs lives_ok (geen exclusion/constraint fires)
select lives_ok(
    $$
    insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_arbeider_pct, bron_url, bron_document)
    select v.status, v.werkgeverscategorie, v.geldig_van, v.geldig_tot, v.basisbijdrage_pct, v.basisfactor_arbeider_pct, v.bron_url, v.bron_document
    from (values
        ('bediende'::text, 1::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.2507::numeric(6,4), null::numeric(6,4), 'x'::text, 'x'::text),
        ('arbeider'::text, 1::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.2507::numeric(6,4), 1.0800::numeric(6,4), 'x'::text, 'x'::text)
    ) as v(status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_arbeider_pct, bron_url, bron_document)
    where not exists (
        select 1 from public.param_rsz t
        where t.status = v.status
          and t.werkgeverscategorie = v.werkgeverscategorie
          and t.geldig_van = v.geldig_van
    )
    $$,
    'param_rsz idempotent re-run lives_ok (geen exclusion constraint fires)'
);

-- Re-run param_structurele insert
select lives_ok(
    $$
    insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, bron_url, bron_document)
    select v.werkgeverscategorie, v.geldig_van, v.geldig_tot, v.forfait, v.coefficient_a, v.coefficient_b, v.bron_url, v.bron_document
    from (values
        (1::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.0000::numeric(18,4), 0.14000000::numeric(12,8), 0.00000000::numeric(12,8), 'x'::text, 'x'::text)
    ) as v(werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, bron_url, bron_document)
    where not exists (
        select 1 from public.param_structurele_vermindering t
        where t.werkgeverscategorie = v.werkgeverscategorie
          and t.geldig_van = v.geldig_van
    )
    $$,
    'param_structurele_vermindering idempotent re-run lives_ok'
);

-- Re-run param_doelgroep insert
select lives_ok(
    $$
    insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, voorwaarden_json, bron_url, bron_document)
    select v.gewest, v.doelgroep, v.geldig_van, v.geldig_tot, v.forfait, v.coefficient, v.voorwaarden_json, v.bron_url, v.bron_document
    from (values
        ('vlaanderen'::text, 'oudere_werknemer'::text, '2024-01-01'::date, '2025-01-01'::date, 600.0000::numeric(18,4), 1.00000000::numeric(12,8), '{}'::jsonb, 'x'::text, 'x'::text)
    ) as v(gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, voorwaarden_json, bron_url, bron_document)
    where not exists (
        select 1 from public.param_doelgroepvermindering t
        where t.gewest = v.gewest
          and t.doelgroep = v.doelgroep
          and t.geldig_van = v.geldig_van
    )
    $$,
    'param_doelgroepvermindering idempotent re-run lives_ok'
);

-- Count-invariant after re-run: count blijft gelijk aan seeded
select is(
    (select count(*)::int from public.param_rsz),
    6,
    'param_rsz count unchanged (6) na idempotent re-run'
);

select is(
    (select count(*)::int from public.param_structurele_vermindering),
    3,
    'param_structurele_vermindering count unchanged (3) na idempotent re-run'
);

select is(
    (select count(*)::int from public.param_doelgroepvermindering),
    6,
    'param_doelgroepvermindering count unchanged (6) na idempotent re-run'
);


------------------------------------------------------------
-- Value spot-checks (4 assertions)
------------------------------------------------------------

-- 1) Arbeider cat 1 heeft 108% basisfactor
select is(
    (select basisfactor_arbeider_pct from public.param_rsz where status = 'arbeider' and werkgeverscategorie = 1),
    1.0800::numeric(6,4),
    'arbeider cat 1 heeft basisfactor 108% (PDF Laag 3 conform)'
);

-- 2) Bediende cat 2 heeft basisbijdrage 24.32%
select is(
    (select basisbijdrage_pct from public.param_rsz where status = 'bediende' and werkgeverscategorie = 2),
    0.2432::numeric(6,4),
    'bediende cat 2 (social profit) heeft basisbijdrage 24.32%'
);

-- 3) Structurele cat 3 heeft forfait 375
select is(
    (select forfait from public.param_structurele_vermindering where werkgeverscategorie = 3),
    375.0000::numeric(18,4),
    'structurele vermindering cat 3 (beschutte werkplaats) heeft forfait 375 EUR'
);

-- 4) Brussel activa_50plus heeft min_leeftijd 55 in voorwaarden_json
select is(
    (select voorwaarden_json->>'min_leeftijd' from public.param_doelgroepvermindering where gewest = 'brussel' and doelgroep = 'activa_50plus'),
    '55',
    'brussel activa_50plus heeft min_leeftijd 55 (Actiris beleid)'
);


------------------------------------------------------------
-- Biconditional cross-check op param_rsz (2 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.param_rsz where status = 'arbeider' and basisfactor_arbeider_pct is not null),
    3,
    'alle 3 arbeider-rijen hebben non-NULL basisfactor_arbeider_pct (biconditional CHECK T-015)'
);

select is(
    (select count(*)::int from public.param_rsz where status = 'bediende' and basisfactor_arbeider_pct is null),
    3,
    'alle 3 bediende-rijen hebben NULL basisfactor_arbeider_pct (biconditional CHECK T-015)'
);


reset role;


select * from finish();
ROLLBACK;
