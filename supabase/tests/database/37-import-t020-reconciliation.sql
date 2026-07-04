BEGIN;
-- Depends on dim_pc seed rows: 200, 302 (see supabase/migrations/20260703020000_dim_pc.sql)
-- Depends on T-020 import migration 20260703170000_...sql

create extension if not exists pgtap;

select plan(20);

set local role service_role;


------------------------------------------------------------
-- Count invariants (4 assertions)
------------------------------------------------------------

select is(
    (select count(*)::int from public.param_wagen_mobiliteit),
    1,
    'param_wagen_mobiliteit has 1 rij (2024 CO2-solidariteitsbijdrage baseline)'
);

select is(
    (select count(*)::int from public.param_bijzondere_bijdragen),
    4,
    'param_bijzondere_bijdragen has 4 rijen (fso, bev, asbest, loonmatiging)'
);

select is(
    (select count(*)::int from public.param_extralegaal),
    4,
    'param_extralegaal has 4 rijen (maaltijdcheque, ecocheque, groepsverzekering, mobiliteitsbudget)'
);

select is(
    (select count(*)::int from public.param_sectorbijdrage),
    4,
    'param_sectorbijdrage has 4 rijen (2 PCs x 2 fondsen)'
);


------------------------------------------------------------
-- Non-null bron_url invariants (4 assertions)
------------------------------------------------------------

select is((select count(*)::int from public.param_wagen_mobiliteit where bron_url is null), 0, 'param_wagen_mobiliteit: geen NULL bron_url');
select is((select count(*)::int from public.param_bijzondere_bijdragen where bron_url is null), 0, 'param_bijzondere_bijdragen: geen NULL bron_url');
select is((select count(*)::int from public.param_extralegaal where bron_url is null), 0, 'param_extralegaal: geen NULL bron_url');
select is((select count(*)::int from public.param_sectorbijdrage where bron_url is null), 0, 'param_sectorbijdrage: geen NULL bron_url');


------------------------------------------------------------
-- Idempotency: lives_ok re-run + count-invariant (8 assertions)
------------------------------------------------------------

select lives_ok(
    $$
    insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, co2_formule_json, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url, bron_document)
    select v.* from (values ('2024-01-01'::date, null::date, '{}'::jsonb, 82::smallint, 31.9900::numeric(18,4), 1.00000000::numeric(12,8), 'x'::text, 'x'::text))
    as v(geldig_van, geldig_tot, co2_formule_json, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url, bron_document)
    where not exists (select 1 from public.param_wagen_mobiliteit t where t.geldig_van = v.geldig_van)
    $$,
    'param_wagen_mobiliteit idempotent re-run lives_ok'
);

select lives_ok(
    $$
    insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, formule_json, bron_url, bron_document)
    select v.* from (values ('fso'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0010::numeric(6,4), '{}'::jsonb, 'x'::text, 'x'::text))
    as v(type, geldig_van, geldig_tot, tarief, formule_json, bron_url, bron_document)
    where not exists (select 1 from public.param_bijzondere_bijdragen t where t.type = v.type and t.geldig_van = v.geldig_van)
    $$,
    'param_bijzondere_bijdragen idempotent re-run lives_ok'
);

select lives_ok(
    $$
    insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url, bron_document)
    select v.* from (values ('maaltijdcheque'::text, '2024-01-01'::date, '2025-01-01'::date, 6.9100::numeric(18,4), 0.0000::numeric(6,4), 'x'::text, 'x'::text))
    as v(voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url, bron_document)
    where not exists (select 1 from public.param_extralegaal t where t.voordeeltype = v.voordeeltype and t.geldig_van = v.geldig_van)
    $$,
    'param_extralegaal idempotent re-run lives_ok'
);

select lives_ok(
    $$
    insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url, bron_document)
    select v.* from (values ('200'::text, 'bestaanszekerheid'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0060::numeric(6,4), 'x'::text, 'x'::text))
    as v(pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url, bron_document)
    where not exists (select 1 from public.param_sectorbijdrage t where t.pc_id = v.pc_id and t.fonds = v.fonds and t.geldig_van = v.geldig_van)
    $$,
    'param_sectorbijdrage idempotent re-run lives_ok'
);

select is((select count(*)::int from public.param_wagen_mobiliteit), 1, 'param_wagen_mobiliteit count unchanged na re-run');
select is((select count(*)::int from public.param_bijzondere_bijdragen), 4, 'param_bijzondere_bijdragen count unchanged na re-run');
select is((select count(*)::int from public.param_extralegaal), 4, 'param_extralegaal count unchanged na re-run');
select is((select count(*)::int from public.param_sectorbijdrage), 4, 'param_sectorbijdrage count unchanged na re-run');


------------------------------------------------------------
-- Value spot-checks (3 assertions)
------------------------------------------------------------

select is(
    (select co2_formule_json->>'factor' from public.param_wagen_mobiliteit),
    '9.0',
    'CO2 formule factor = 9.0 (RSZ patronale bijdrage-formule constante)'
);

select is(
    (select tarief from public.param_bijzondere_bijdragen where type = 'loonmatiging'),
    0.0775::numeric(6,4),
    'loonmatiging tarief = 7.75% (patronale globale loonmatigingsbijdrage 2024)'
);

select is(
    (select taks_pct from public.param_extralegaal where voordeeltype = 'groepsverzekering'),
    0.1326::numeric(6,4),
    'groepsverzekering taks_pct = 13.26% (premietaks 4.4% + RSZ 8.86% per PDF)'
);


------------------------------------------------------------
-- Cross-cutting: POC_UNVERIFIED_2024 prefix in bron_document (1 assertion)
------------------------------------------------------------

select is(
    (select
        (select count(*) from public.param_wagen_mobiliteit where bron_document like '[POC_UNVERIFIED_2024]%')
      + (select count(*) from public.param_bijzondere_bijdragen where bron_document like '[POC_UNVERIFIED_2024]%')
      + (select count(*) from public.param_extralegaal where bron_document like '[POC_UNVERIFIED_2024]%')
      + (select count(*) from public.param_sectorbijdrage where bron_document like '[POC_UNVERIFIED_2024]%')
    )::int,
    13,
    'alle 13 T-020 rijen hebben [POC_UNVERIFIED_2024] prefix (pre-productie deploy-gate)'
);


reset role;


select * from finish();
ROLLBACK;
