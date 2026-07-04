-- ================================================================
-- T-018: Import 2024 baseline — RSZ + structurele + doelgroepverminderingen
-- ================================================================
--
-- !! POC_UNVERIFIED — CROSS-CHECK RSZ INSTRUCTIEGIDS 2024 VOOR PRODUCTIE-DEPLOY !!
--
-- Waarden zijn plausibele orde-van-grootte voor 2024 jaargang (BE-only per POC-scope
-- + ISS-031). Concrete tarieven kunnen afwijken; iedere rij heeft bron_document met
-- '[POC_UNVERIFIED_2024]' prefix zodat pre-productie query kan detecteren:
--
--     select count(*) from param_rsz where bron_document like '[POC_UNVERIFIED_2024]%';
--     -- > 0 = niet-geverifieerde POC-seed nog aanwezig, block deploy
--
-- Idempotent via `insert ... select from values ... where not exists` per tabel
-- (3 statements ipv 15 individuele INSERTs). Business-key deduplication:
--   - param_rsz: (status, werkgeverscategorie, geldig_van)
--   - param_structurele_vermindering: (werkgeverscategorie, geldig_van)
--   - param_doelgroepvermindering: (gewest, doelgroep, geldig_van)
--
-- WHERE NOT EXISTS is niet strict concurrent-safe (twee parallel-sessies kunnen
-- beide pass NOT EXISTS check, dan botsen op exclusion constraint). Acceptabel
-- voor Supabase migration runner die migraties serialized apply. Voor runtime
-- imports (edge function): unique constraint op business-key nodig — out-of-scope.
--
-- EE4 (value-range CHECK constraints op parameterlaag) heruitgetrokken naar
-- ISS-032. Deze migration blijft data-import only.
--
-- Bron: RSZ instructiegids 2024/Q1, PDF Laag 3, VDAB/Forem/Actiris KBs 2024.


-- ================================================================
-- 1) param_rsz — 6 rijen (2 status × 3 werkgeverscategorie), geldig 2024-01-01 → 2025-01-01
-- ================================================================

insert into public.param_rsz (status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url, bron_document)
select v.status, v.werkgeverscategorie, v.geldig_van, v.geldig_tot, v.basisbijdrage_pct, v.basisfactor_pct, v.bron_url, v.bron_document
from (values
    ('bediende'::text, 1::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.2507::numeric(6,4), null::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ instructiegids 2024/1 — basisbijdrage cat 1 (25,07% incl. loonmatiging)'::text),
    ('bediende'::text, 2::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.2432::numeric(6,4), null::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ instructiegids 2024/1 — social profit cat 2 (24,32%)'::text),
    ('bediende'::text, 3::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.1707::numeric(6,4), null::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ instructiegids 2024/1 — beschutte werkplaats cat 3 (17,07%)'::text),
    ('arbeider'::text, 1::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.2507::numeric(6,4), 1.0800::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ instructiegids 2024/1 — arbeider cat 1 + 108% arbeidersgrondslag'::text),
    ('arbeider'::text, 2::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.2432::numeric(6,4), 1.0800::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ instructiegids 2024/1 — arbeider social profit + 108%'::text),
    ('arbeider'::text, 3::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.1707::numeric(6,4), 1.0800::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ instructiegids 2024/1 — arbeider beschutte + 108%'::text)
) as v(status, werkgeverscategorie, geldig_van, geldig_tot, basisbijdrage_pct, basisfactor_pct, bron_url, bron_document)
where not exists (
    select 1 from public.param_rsz t
    where t.status = v.status
      and t.werkgeverscategorie = v.werkgeverscategorie
      and t.geldig_van = v.geldig_van
);


-- ================================================================
-- 2) param_structurele_vermindering — 3 rijen (3 werkgeverscategorie), geldig 2024-01-01 → 2025-01-01
-- ================================================================
-- Formule: R = F - a*(S0-S) - b*(S1-S). Pro rata mu in cascade.

insert into public.param_structurele_vermindering (werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, bron_url, bron_document)
select v.werkgeverscategorie, v.geldig_van, v.geldig_tot, v.forfait, v.coefficient_a, v.coefficient_b, v.bron_url, v.bron_document
from (values
    (1::smallint, '2024-01-01'::date, '2025-01-01'::date, 0.0000::numeric(18,4), 0.14000000::numeric(12,8), 0.40000000::numeric(12,8), 'https://www.socialsecurity.be/employer/instructions/'::text, 'RSZ instructiegids 1 april 2024 — cat 1 algemeen/prive: R = 0.14 × max(0, 10797.67 - S) + 0.40 × max(0, 6807.18 - S). Cross-checked easypay-group.com.'::text),
    (2::smallint, '2024-01-01'::date, '2025-01-01'::date, 49.0000::numeric(18,4), 0.26410000::numeric(12,8), 0.00000000::numeric(12,8), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ 2024 — cat 2 social profit: forfait + lage-lonencomponent'::text),
    (3::smallint, '2024-01-01'::date, '2025-01-01'::date, 375.0000::numeric(18,4), 0.17140000::numeric(12,8), 0.06860000::numeric(12,8), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ 2024 — cat 3 beschutte werkplaats: forfait + dubbele component'::text)
) as v(werkgeverscategorie, geldig_van, geldig_tot, forfait, coefficient_a, coefficient_b, bron_url, bron_document)
where not exists (
    select 1 from public.param_structurele_vermindering t
    where t.werkgeverscategorie = v.werkgeverscategorie
      and t.geldig_van = v.geldig_van
);


-- ================================================================
-- 3) param_doelgroepvermindering — 6 rijen (2 doelgroepen × 3 gewesten), geldig 2024-01-01 → 2025-01-01
-- ================================================================
-- Post-6e-Staatshervorming regionale beleid: VDAB (Vlaanderen), Forem (Wallonie), Actiris (Brussel).

insert into public.param_doelgroepvermindering (gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, voorwaarden_json, bron_url, bron_document)
select v.gewest, v.doelgroep, v.geldig_van, v.geldig_tot, v.forfait, v.coefficient, v.voorwaarden_json, v.bron_url, v.bron_document
from (values
    ('vlaanderen'::text, 'oudere_werknemer'::text, '2024-01-01'::date, '2025-01-01'::date, 600.0000::numeric(18,4), 1.00000000::numeric(12,8), '{"min_leeftijd":60,"max_refertekwartaalloon_eur":13945}'::jsonb, 'https://www.vlaanderen.be/doelgroepvermindering'::text, '[POC_UNVERIFIED_2024] VDAB 2024 — zittende oudere 60+'::text),
    ('vlaanderen'::text, 'jongere_zonder_diploma'::text, '2024-01-01'::date, '2025-01-01'::date, 1000.0000::numeric(18,4), 1.00000000::numeric(12,8), '{"max_leeftijd":25,"kwalificatie":"laaggeschoold","max_refertekwartaalloon_eur":9000}'::jsonb, 'https://www.vlaanderen.be/doelgroepvermindering'::text, '[POC_UNVERIFIED_2024] VDAB 2024 — laaggeschoolde jongere <25'::text),
    ('wallonie'::text, 'impulsion_jongere'::text, '2024-01-01'::date, '2025-01-01'::date, 500.0000::numeric(18,4), 1.00000000::numeric(12,8), '{"max_leeftijd":25,"kwalificatie":"laag_of_middel_geschoold","duur_maanden":24}'::jsonb, 'https://www.forem.be/entreprises/impulsion'::text, '[POC_UNVERIFIED_2024] Forem 2024 — Impulsion -25 ans'::text),
    ('wallonie'::text, 'impulsion_langdurig_werkloos'::text, '2024-01-01'::date, '2025-01-01'::date, 500.0000::numeric(18,4), 1.00000000::numeric(12,8), '{"werkloos_min_maanden":12,"duur_maanden":36}'::jsonb, 'https://www.forem.be/entreprises/impulsion'::text, '[POC_UNVERIFIED_2024] Forem 2024 — Impulsion 12M+ langdurig werkloos'::text),
    ('brussel'::text, 'activa_50plus'::text, '2024-01-01'::date, '2025-01-01'::date, 1000.0000::numeric(18,4), 1.00000000::numeric(12,8), '{"min_leeftijd":55,"werkloos_min_maanden":6}'::jsonb, 'https://werk-economie-emploi.brussels/nl/activa'::text, '[POC_UNVERIFIED_2024] Actiris 2024 — Activa 55+'::text),
    ('brussel'::text, 'activa_langdurig_werkloos'::text, '2024-01-01'::date, '2025-01-01'::date, 350.0000::numeric(18,4), 1.00000000::numeric(12,8), '{"werkloos_min_maanden":12,"duur_maanden":30}'::jsonb, 'https://werk-economie-emploi.brussels/nl/activa'::text, '[POC_UNVERIFIED_2024] Actiris 2024 — Activa langdurig werklozen'::text)
) as v(gewest, doelgroep, geldig_van, geldig_tot, forfait, coefficient, voorwaarden_json, bron_url, bron_document)
where not exists (
    select 1 from public.param_doelgroepvermindering t
    where t.gewest = v.gewest
      and t.doelgroep = v.doelgroep
      and t.geldig_van = v.geldig_van
);
