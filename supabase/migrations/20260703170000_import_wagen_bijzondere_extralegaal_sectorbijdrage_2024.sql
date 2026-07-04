-- ================================================================
-- T-020: Import 2024 baseline — wagen + bijzondere_bijdragen + extralegaal + sectorbijdrage
-- ================================================================
--
-- !! POC_UNVERIFIED — CROSS-CHECK RSZ / FOD FIN / KBs VOOR PRODUCTIE-DEPLOY !!
--
-- LAATSTE import-ticket. Vult de resterende 4 parameter-tabellen uit T-017.
-- Sluit Phase 4 parameter-laag import volledig af — rekencascade (T-026+)
-- heeft alle data die nodig is.
--
-- 13 rijen totaal (1 + 4 + 4 + 4). Idempotent via WHERE NOT EXISTS.
--
-- Bijzondere sentinel: param_extralegaal.max_wg = 999999.9999 voor
-- 'groepsverzekering' = 'geen absolute cap'. bron_document markeert dit
-- via prefix [SENTINEL_MAX_WG] zodat rekencascade dit kan detecteren.
-- Correcte fix (schema NULL toelaten) → ISS-032.
--
-- Loonmatiging tarief 7.75% is patronale globale loonmatigingsbijdrage;
-- centenindex-specifieke berekening (50% indexbesparing) staat in formule_json
-- als toelichting — rekencascade past de formule toe met param_index-drempel.


-- ================================================================
-- 1) param_wagen_mobiliteit — 1 rij (CO2-solidariteitsbijdrage)
-- ================================================================

insert into public.param_wagen_mobiliteit (geldig_van, geldig_tot, co2_formule_json, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url, bron_document)
select v.geldig_van, v.geldig_tot, v.co2_formule_json, v.referentie_co2, v.minimumbijdrage, v.vaa_coefficient, v.bron_url, v.bron_document
from (values
    ('2024-01-01'::date, null::date,
     '{"formule":"max(((co2*factor)-correctie)*indexatie/12, minimum)","factor":9.0,"correctie_benzine":768.0,"correctie_diesel":600.0,"correctie_lpg":990.0,"indexatie_2024":1.5359,"referentie_benzine_gkm":91,"referentie_diesel_gkm":82,"vaa_min_jaar":1600}'::jsonb,
     82::smallint,
     31.9900::numeric(18,4),
     1.00000000::numeric(12,8),
     'https://www.socialsecurity.be/employer/instructions/'::text,
     '[POC_UNVERIFIED_2024] RSZ 2024/1 CO2-solidariteitsbijdrage — factor 9.0, indexatie 1.5359, referentie 82g diesel / 91g benzine, min €31.99/maand'::text)
) as v(geldig_van, geldig_tot, co2_formule_json, referentie_co2, minimumbijdrage, vaa_coefficient, bron_url, bron_document)
where not exists (
    select 1 from public.param_wagen_mobiliteit t
    where t.geldig_van = v.geldig_van
);


-- ================================================================
-- 2) param_bijzondere_bijdragen — 4 rijen (één per CHECK-enum type)
-- ================================================================

insert into public.param_bijzondere_bijdragen (type, geldig_van, geldig_tot, tarief, formule_json, bron_url, bron_document)
select v.type, v.geldig_van, v.geldig_tot, v.tarief, v.formule_json, v.bron_url, v.bron_document
from (values
    ('fso'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0010::numeric(6,4), '{"basis":"brutoloon_108","toepassing":"wg >= 20 wn"}'::jsonb, 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ 2024 — FSO Fonds Sluiting Ondernemingen basisbijdrage 0.10%'::text),
    ('bev'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0016::numeric(6,4), '{"basis":"brutoloon_108","toepassing":"wg >= 10 wn"}'::jsonb, 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ 2024 — BEV Bijzondere bijdrage werkloosheid 0.16%'::text),
    ('asbest'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0001::numeric(6,4), '{"basis":"brutoloon_108"}'::jsonb, 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] RSZ 2024 — Asbestfonds 0.01%'::text),
    -- Loonmatiging: tarief RESET naar 0. RSZ post-tax-shift 2018 heeft
    -- loonmatiging (5.12%) al VERWERKT in basisbijdrage 25% (stap 2). Dubbelrekening
    -- geeft ~7.5% te veel patronale kost. Row houden voor centenindex-berekening
    -- die conditioneel is op loonmatiging-aanwezigheid in stap 5 productie-variant.
    ('loonmatiging'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0000::numeric(6,4), '{"formule":"0.5 * indexbesparing","cap":"drempel_bruto_uit_param_index","basis_rsz":"brutoloon_108","toelichting":"Centenindex loonmatigingsbijdrage = 50% van indexbesparing boven drempel. Basistarief 0 omdat loonmatiging al in stap 2 basisbijdrage 25% (post-tax-shift 2018 architecture)."}'::jsonb, 'https://www.socialsecurity.be/employer/instructions/'::text, 'RSZ 2024 post-tax-shift — Loonmatigingsbijdrage patronaal 5.12% al opgenomen in stap 2 basisbijdrage 25.07%. Tarief hier op 0 voor dubbelrekening-preventie. Bron VBO-FEB Q1 2024.'::text)
) as v(type, geldig_van, geldig_tot, tarief, formule_json, bron_url, bron_document)
where not exists (
    select 1 from public.param_bijzondere_bijdragen t
    where t.type = v.type
      and t.geldig_van = v.geldig_van
);


-- ================================================================
-- 3) param_extralegaal — 4 rijen (per voordeeltype)
-- ================================================================
-- Sentinel: groepsverzekering.max_wg = 999999.9999 → "geen absolute cap"
-- markeer via bron_document [SENTINEL_MAX_WG] tag. Cascade moet dit checken.

insert into public.param_extralegaal (voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url, bron_document)
select v.voordeeltype, v.geldig_van, v.geldig_tot, v.max_wg, v.taks_pct, v.bron_url, v.bron_document
from (values
    ('maaltijdcheque'::text, '2024-01-01'::date, '2025-01-01'::date, 6.9100::numeric(18,4), 0.0000::numeric(6,4), 'https://financien.belgium.be/nl/ondernemingen/personeel_en_loon/voordelen_alle_aard/maaltijdcheques'::text, '[POC_UNVERIFIED_2024] FOD Fin 2024 — Max wg-tussenkomst EUR 6.91 per maaltijdcheque per dag'::text),
    ('ecocheque'::text, '2024-01-01'::date, '2025-01-01'::date, 250.0000::numeric(18,4), 0.0000::numeric(6,4), 'https://www.rsz.fgov.be/nl/werkgevers-en-de-rsz/ecocheques'::text, '[POC_UNVERIFIED_2024] RSZ 2024 — Ecocheques max EUR 250 per jaar per werknemer'::text),
    ('groepsverzekering'::text, '2024-01-01'::date, '2025-01-01'::date, 999999.9999::numeric(18,4), 0.1326::numeric(6,4), 'https://financien.belgium.be/nl/ondernemingen/personeel_en_loon/groepsverzekering'::text, '[POC_UNVERIFIED_2024][SENTINEL_MAX_WG] FOD Fin — Premietaks 4.4% + RSZ 8.86% = 13.26%; max_wg=999999.9999 is sentinel voor GEEN ABSOLUTE CAP (correcte modellering deferred naar ISS-032)'::text),
    ('mobiliteitsbudget'::text, '2024-01-01'::date, '2025-01-01'::date, 16875.0000::numeric(18,4), 0.0000::numeric(6,4), 'https://mobiliteitsbudget.belgie.be/'::text, '[POC_UNVERIFIED_2024] Wet 17.03.2019 (2024 geindexeerd) — Cap 20% brutoloon met absoluut plafond EUR 16.875/jaar'::text)
) as v(voordeeltype, geldig_van, geldig_tot, max_wg, taks_pct, bron_url, bron_document)
where not exists (
    select 1 from public.param_extralegaal t
    where t.voordeeltype = v.voordeeltype
      and t.geldig_van = v.geldig_van
);


-- ================================================================
-- 4) param_sectorbijdrage — 4 rijen (2 PCs × 2 fondsen)
-- ================================================================

insert into public.param_sectorbijdrage (pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url, bron_document)
select v.pc_id, v.fonds, v.geldig_van, v.geldig_tot, v.tarief, v.bron_url, v.bron_document
from (values
    ('200'::text, 'bestaanszekerheid'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0060::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] PC 200 aanvullend bedienden — sociaal fonds bestaanszekerheid 0.60%'::text),
    ('200'::text, 'vorming'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0010::numeric(6,4), 'https://www.socialsecurity.be/employer/instructions/'::text, '[POC_UNVERIFIED_2024] PC 200 vormingsbijdrage 0.10%'::text),
    ('302'::text, 'bestaanszekerheid'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0050::numeric(6,4), 'https://www.horecafederatie.be/'::text, '[POC_UNVERIFIED_2024] PC 302 horeca — sociaal fonds bestaanszekerheid 0.50%'::text),
    ('302'::text, 'vorming'::text, '2024-01-01'::date, '2025-01-01'::date, 0.0015::numeric(6,4), 'https://www.horeca-vorming.be/'::text, '[POC_UNVERIFIED_2024] PC 302 vormingsbijdrage Horeca Forma 0.15%'::text)
) as v(pc_id, fonds, geldig_van, geldig_tot, tarief, bron_url, bron_document)
where not exists (
    select 1 from public.param_sectorbijdrage t
    where t.pc_id = v.pc_id
      and t.fonds = v.fonds
      and t.geldig_van = v.geldig_van
);
