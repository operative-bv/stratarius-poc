-- ================================================================
-- T-019: Import 2024 baseline — arbeidsduur + vakantiegeld + index
-- ================================================================
--
-- !! POC_UNVERIFIED — CROSS-CHECK RSZ/FOD ECONOMIE/RJV VOOR PRODUCTIE-DEPLOY !!
--
-- 10 rijen concrete parameter-waarden voor 4 belangrijke PCs (111, 124, 200, 302)
-- + 2 regime-rijen voor vakantiegeld. BE-only per POC-scope (ISS-031).
--
-- Idempotent via `insert ... select from values ... where not exists` per tabel.
-- Business-key deduplication:
--   - param_arbeidsduur: (pc_id, geldig_van)
--   - param_vakantiegeld: (regime, geldig_van)
--   - param_index: (pc_id, geldig_van)
--
-- Loonmatigingsbijdrage (centenindex 50% van indexbesparing) is aparte concern —
-- niet hier, wel in T-020 param_bijzondere_bijdragen als type='loonmatiging'.
--
-- Waarden: RSZ instructiegids + FOD Economie indexcijfers + RJV standaarden 2024.


-- ================================================================
-- 1) param_arbeidsduur — 4 rijen (S-referentie voor mu = Q/S per PC)
-- ================================================================

insert into public.param_arbeidsduur (pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url, bron_document)
select v.pc_id, v.geldig_van, v.geldig_tot, v.gemiddelde_wekelijkse_uren, v.bron_url, v.bron_document
from (values
    ('111'::text, '2024-01-01'::date, '2025-01-01'::date, 38.0000::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] PC 111 metaal — standaard 38u/week per sectorale CAO'::text),
    ('124'::text, '2024-01-01'::date, '2025-01-01'::date, 40.0000::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] PC 124 bouw — 40u/week nominaal (ADV-compensatie naar 38u effectief)'::text),
    ('200'::text, '2024-01-01'::date, '2025-01-01'::date, 38.0000::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] PC 200 aanvullend bedienden — standaard 38u/week'::text),
    ('302'::text, '2024-01-01'::date, '2025-01-01'::date, 38.0000::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] PC 302 horeca — 38u/week standaard'::text)
) as v(pc_id, geldig_van, geldig_tot, gemiddelde_wekelijkse_uren, bron_url, bron_document)
where not exists (
    select 1 from public.param_arbeidsduur t
    where t.pc_id = v.pc_id
      and t.geldig_van = v.geldig_van
);


-- ================================================================
-- 2) param_vakantiegeld — 2 rijen (per regime)
-- ================================================================
-- Arbeider: dubbel_pct = 0.0000 want vakantiekas dekt zowel enkel als dubbel
-- via 15.38%-bijdrage op 108%-loonbasis. Directe WG-dubbel component = 0.
-- Splitsen zou dubbeltelling veroorzaken.
-- Bediende: enkel 7.67% doorbetaald tijdens vakantie + dubbel 92% van maandloon.

insert into public.param_vakantiegeld (regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url, bron_document)
select v.regime, v.geldig_van, v.geldig_tot, v.enkel_pct, v.dubbel_pct, v.bron_url, v.bron_document
from (values
    ('arbeider'::text, '2024-01-01'::date, '2025-01-01'::date, 0.1538::numeric(6,4), 0.0000::numeric(6,4), 'https://www.rjv.be/'::text, '[POC_UNVERIFIED_2024] Arbeider 15.38% vakantiekas-bijdrage op 108% basisloon; dubbel_pct=0 want vakantiekas betaalt zowel enkel als dubbel'::text),
    ('bediende'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0767::numeric(6,4), 0.9200::numeric(6,4), 'https://www.rjv.be/'::text, '[POC_UNVERIFIED_2024] Bediende enkel 7.67% doorbetaald + dubbel 92% van maandloon (RJV standaard 2024)'::text)
) as v(regime, geldig_van, geldig_tot, enkel_pct, dubbel_pct, bron_url, bron_document)
where not exists (
    select 1 from public.param_vakantiegeld t
    where t.regime = v.regime
      and t.geldig_van = v.geldig_van
);


-- ================================================================
-- 3) param_index — 4 rijen (indexcoefficient + centenindex drempel)
-- ================================================================
-- drempel_bruto = 4000 EUR per PDF Laag 3 centenindex-regel: min(bruto, EUR 4000).
-- Loonmatigingsbijdrage (50% indexbesparing) leeft in param_bijzondere_bijdragen T-020.

insert into public.param_index (pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url, bron_document)
select v.pc_id, v.geldig_van, v.geldig_tot, v.index_coefficient, v.drempel_bruto, v.bron_url, v.bron_document
from (values
    ('111'::text, '2024-01-01'::date, '2025-01-01'::date, 1.020000::numeric(10,6), 4000.0000::numeric(18,4), 'https://economie.fgov.be/nl/themas/ondernemingen/indexcijfers'::text, '[POC_UNVERIFIED_2024] PC 111 metaal — 2% jaarlijkse indexatie'::text),
    ('124'::text, '2024-01-01'::date, '2025-01-01'::date, 1.015000::numeric(10,6), 4000.0000::numeric(18,4), 'https://economie.fgov.be/nl/themas/ondernemingen/indexcijfers'::text, '[POC_UNVERIFIED_2024] PC 124 bouw — 1.5% indexcoefficient'::text),
    ('200'::text, '2024-01-01'::date, '2025-01-01'::date, 1.020000::numeric(10,6), 4000.0000::numeric(18,4), 'https://economie.fgov.be/nl/themas/ondernemingen/indexcijfers'::text, '[POC_UNVERIFIED_2024] PC 200 aanvullend bedienden — spilindex-gebaseerd 2%'::text),
    ('302'::text, '2024-01-01'::date, '2025-01-01'::date, 1.020000::numeric(10,6), 4000.0000::numeric(18,4), 'https://economie.fgov.be/nl/themas/ondernemingen/indexcijfers'::text, '[POC_UNVERIFIED_2024] PC 302 horeca — 2% indexatie'::text)
) as v(pc_id, geldig_van, geldig_tot, index_coefficient, drempel_bruto, bron_url, bron_document)
where not exists (
    select 1 from public.param_index t
    where t.pc_id = v.pc_id
      and t.geldig_van = v.geldig_van
);
