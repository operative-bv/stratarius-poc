-- ================================================================
-- Fase 3 (fiscale audit): import 2025 + 2026 param waardes
-- ================================================================
--
-- Op basis van uitgebreide research tegen RSZ instructiegids, VBO, SD
-- Worx, Attentia, Securex, Partena, Acerta bronnen (juli 2026).
--
-- Belangrijkste wijzigingen 2024→2026:
-- 1. RSZ basisbijdrage: 0.2507 (POC benadering) → 0.2500 (werkelijk tax-shift)
-- 2. Structurele vermindering: 3 shifts (2025-04, 2025-07 γ-daling, 2026-01)
-- 3. RSZ plafond: 85.000 → 86.700 (2026-01-01)
-- 4. Wagen CO2 multiplier: 2.75 → 4.0 (2026-01-01)
-- 5. FSO klassiek: 0.17% → 0.32% <20wn, 0.22% → 0.37% ≥20wn (2026-01-01)
-- 6. Maaltijdcheque max: 6.91 → 8.91 (2026-01-01)
-- 7. Vlaanderen doelgroepvermindering ouderen: afgeschaft 2025-07-01
-- 8. Vakantiegeld: ongewijzigd (bestaande 2024 rijen open-ended, gelden)
-- ================================================================


-- ================================================================
-- 1. param_rsz — nieuwe rijen 2025-01-01 en 2026-01-01
-- ================================================================
-- Tax-shift tarief 0.2500 (bediende + arbeider, cat 1 en 3).
-- Cat 2 social profit: 0.3232 (geen tax-shift korting, volle loonmatiging).
-- Basisfactor voor arbeider: 1.08 (grondslag × 8% verhoging).

-- Sluit bestaande 2024 rijen af per 2025-01-01
update public.param_rsz
    set geldig_tot = '2025-01-01'
    where geldig_van = '2024-01-01' and geldig_tot is null;

insert into public.param_rsz (
    status, werkgeverscategorie, geldig_van, geldig_tot,
    basisbijdrage_pct, basisfactor_pct,
    bron_url, bron_document
) values
    -- 2025 rijen
    ('bediende', 1::smallint, '2025-01-01'::date, null, 0.2500::numeric(6, 4), 1.0000::numeric(6, 4),
     'https://www.socialsecurity.be/employer/instructions/dmfa/nl/latest/instructions/socialsecuritycontributions/contributions.html',
     'RSZ instructies 2025: tax-shift tarief 25.00% (19.88% basis + 5.12% loonmatiging)'),
    ('arbeider', 1::smallint, '2025-01-01'::date, null, 0.2500::numeric(6, 4), 1.08::numeric(6, 4),
     'https://www.socialsecurity.be/employer/instructions/dmfa/nl/latest/instructions/socialsecuritycontributions/contributions.html',
     'RSZ instructies 2025: arbeider cat 1 met 108% grondslag'),
    ('bediende', 2::smallint, '2025-01-01'::date, null, 0.3232::numeric(6, 4), 1.0000::numeric(6, 4),
     'https://www.vbo-feb.be/nl/nieuws/sociale-bijdragen-eerste-kwartaal-2025/',
     'VBO Q1 2025: cat 2 social profit 24.92% basis + 7.48% loonmatiging = 32.32%'),
    ('arbeider', 2::smallint, '2025-01-01'::date, null, 0.3232::numeric(6, 4), 1.08::numeric(6, 4),
     'https://www.vbo-feb.be/nl/nieuws/sociale-bijdragen-eerste-kwartaal-2025/',
     'VBO Q1 2025: arbeider cat 2'),
    ('bediende', 3::smallint, '2025-01-01'::date, null, 0.2500::numeric(6, 4), 1.0000::numeric(6, 4),
     'https://www.socialsecurity.be/employer/instructions/dmfa/nl/latest/instructions/socialsecuritycontributions/contributions.html',
     'RSZ 2025: cat 3 beschutte werkplaats idem cat 1'),
    ('arbeider', 3::smallint, '2025-01-01'::date, null, 0.2500::numeric(6, 4), 1.08::numeric(6, 4),
     'https://www.socialsecurity.be/employer/instructions/dmfa/nl/latest/instructions/socialsecuritycontributions/contributions.html',
     'RSZ 2025: arbeider cat 3')
on conflict do nothing;


-- ================================================================
-- 2. param_structurele_vermindering — 3 shifts in 2025-2026
-- ================================================================
-- 2025-04-01: geherindexeerde drempels (S0 omhoog), γ blijft 0.21
-- 2025-07-01: γ verlaagd 0.21 → 0.15, S1 omhoog 6807.18 → 9360.00
-- 2026-01-01: verdere herindexering drempels

update public.param_structurele_vermindering
    set geldig_tot = '2025-04-01'
    where geldig_van = '2024-01-01' and geldig_tot is null;

insert into public.param_structurele_vermindering (
    werkgeverscategorie, geldig_van, geldig_tot,
    forfait, coefficient_a, coefficient_b,
    drempel_s0, drempel_s1,
    bron_url, bron_document
) values
    -- 2025 Q2-Q3 (2025-04-01 → 2025-07-01): herindexering
    (1::smallint, '2025-04-01'::date, '2025-07-01'::date,
     0::numeric(18, 4), 0.14000000::numeric(12, 8), 0.21000000::numeric(12, 8),
     11233.89::numeric(18, 4), 8400.00::numeric(18, 4),
     'https://www.socialsecurity.be/employer/instructions/dmfa/nl/2025-2/instructions/deductions/structuralreduction_targetgroupreductions/structuralreduction.html',
     'RSZ 2025 Q2: cat 1 herindexering S0 10797.67 → 11233.89, S1 6807.18 → 8400'),
    (2::smallint, '2025-04-01'::date, '2025-07-01'::date,
     79::numeric(18, 4), 0.23000000::numeric(12, 8), 0.15000000::numeric(12, 8),
     9780.00::numeric(18, 4), 9780.00::numeric(18, 4),
     'https://www.socialsecurity.be/employer/instructions/dmfa/nl/2025-2/instructions/deductions/structuralreduction_targetgroupreductions/structuralreduction.html',
     '[POC_UNVERIFIED_2025] cat 2 social profit — Partena tabel niet publiek toegankelijk'),
    (3::smallint, '2025-04-01'::date, '2025-07-01'::date,
     495::numeric(18, 4), 0.17850000::numeric(12, 8), 0.21000000::numeric(12, 8),
     11557.16::numeric(18, 4), 8400.00::numeric(18, 4),
     'https://www.partena-professional.be/en/our-insights/infoflashes/nsso-structural-reduction-1-april-2025',
     '[POC_UNVERIFIED_2025] cat 3 beschutte werkplaats zonder loonmatiging — cross-check nodig'),

    -- 2025 Q3-Q4 (2025-07-01 → 2026-01-01): γ SHIFT 0.21 → 0.15 + S1 omhoog
    (1::smallint, '2025-07-01'::date, '2026-01-01'::date,
     0::numeric(18, 4), 0.14000000::numeric(12, 8), 0.15000000::numeric(12, 8),
     11233.89::numeric(18, 4), 9360.00::numeric(18, 4),
     'https://www.agoria.be/nl/diensten/expertise/hr-legal-social-dialogue/aanwerven-tewerkstellen-ontslaan/sociale-zekerheid/rsz-bijdragen-verminderingen-en-formaliteiten/aanpassing-parameters-structurele-rsz-vermindering-vanaf-het-derde-kwartaal-2025',
     'Regeerakkoord: γ verlaagd 0.21 → 0.15 vanaf 2025-07-01, S1 6807.18 → 9360.00'),
    (2::smallint, '2025-07-01'::date, '2026-01-01'::date,
     79::numeric(18, 4), 0.23000000::numeric(12, 8), 0.15000000::numeric(12, 8),
     9780.00::numeric(18, 4), 9780.00::numeric(18, 4),
     'https://www.agoria.be/nl/diensten/expertise/hr-legal-social-dialogue/aanwerven-tewerkstellen-ontslaan/sociale-zekerheid/rsz-bijdragen-verminderingen-en-formaliteiten/aanpassing-parameters-structurele-rsz-vermindering-vanaf-het-derde-kwartaal-2025',
     '[POC_UNVERIFIED_2025_Q3] cat 2 social profit Q3'),
    (3::smallint, '2025-07-01'::date, '2026-01-01'::date,
     495::numeric(18, 4), 0.17850000::numeric(12, 8), 0.15000000::numeric(12, 8),
     11557.16::numeric(18, 4), 9360.00::numeric(18, 4),
     'https://www.agoria.be/nl/diensten/expertise/hr-legal-social-dialogue/aanwerven-tewerkstellen-ontslaan/sociale-zekerheid/rsz-bijdragen-verminderingen-en-formaliteiten/aanpassing-parameters-structurele-rsz-vermindering-vanaf-het-derde-kwartaal-2025',
     '[POC_UNVERIFIED_2025_Q3] cat 3 beschutte werkplaats Q3'),

    -- 2026 Q1+ (2026-01-01 → open): verdere herindexering
    (1::smallint, '2026-01-01'::date, null,
     0::numeric(18, 4), 0.14000000::numeric(12, 8), 0.15000000::numeric(12, 8),
     11458.57::numeric(18, 4), 9547.20::numeric(18, 4),
     'https://www.partena-professional.be/en/our-insights/infoflashes/nsso-structural-reduction-1-januari-2026',
     'Partena 2026-01-01: cat 1 geherindexeerd S0=11458.57, S1=9547.20'),
    (2::smallint, '2026-01-01'::date, null,
     79::numeric(18, 4), 0.23000000::numeric(12, 8), 0.15000000::numeric(12, 8),
     9975.60::numeric(18, 4), 9975.60::numeric(18, 4),
     'https://www.partena-professional.be/en/our-insights/infoflashes/nsso-structural-reduction-1-januari-2026',
     'Partena 2026-01-01: cat 2 social profit geherindexeerd'),
    (3::smallint, '2026-01-01'::date, null,
     495::numeric(18, 4), 0.17850000::numeric(12, 8), 0.15000000::numeric(12, 8),
     11788.30::numeric(18, 4), 9547.20::numeric(18, 4),
     'https://www.partena-professional.be/en/our-insights/infoflashes/nsso-structural-reduction-1-januari-2026',
     'Partena 2026-01-01: cat 3 beschutte werkplaats geherindexeerd')
on conflict do nothing;


-- ================================================================
-- 3. param_plafond — kwartaal 85k → 86.7k per 2026-01-01
-- ================================================================
-- Text-PK per periode zodat effective-dating expressie kan (was nooit
-- geseed). land_id + bijdragetype in exclusion constraint voor overlap check.

insert into public.param_plafond (
    param_plafond_id, land_id, bijdragetype,
    geldig_van, geldig_tot,
    jaarplafond, kwartaalplafond,
    bron_url, bron_document
) values
    ('structurele_vermindering_plafond_2025', 'BE', 'structurele_vermindering',
     '2025-01-01'::date, '2026-01-01'::date,
     340000::numeric(18, 4), 85000::numeric(18, 4),
     'https://www.besox.be/plafond-berekeningsbasis-patronale-rsz-bijdragen/',
     'besox 2025: RSZ plafond kwartaal €85.000 / jaar €340.000'),
    ('structurele_vermindering_plafond_2026', 'BE', 'structurele_vermindering',
     '2026-01-01'::date, null,
     346800::numeric(18, 4), 86700::numeric(18, 4),
     'https://www.besox.be/plafond-berekeningsbasis-patronale-rsz-bijdragen/',
     'besox 2026: geïndexeerd naar €86.700 kwartaal / €346.800 jaar')
on conflict do nothing;


-- ================================================================
-- 4. param_wagen_mobiliteit — multiplier 2.75 → 4.0 per 2026-01-01
-- ================================================================
update public.param_wagen_mobiliteit
    set geldig_tot = '2025-01-01'
    where geldig_van = '2024-01-01' and geldig_tot is null;

-- 2025-01-01 rij: multiplier 2.75 (was al 2024 waarde)
-- 2026-01-01 rij: multiplier 4.0 + geïndexeerd
insert into public.param_wagen_mobiliteit (
    geldig_van, geldig_tot,
    co2_formule_json, referentie_co2, minimumbijdrage, vaa_coefficient,
    bron_url, bron_document
) values
    ('2025-01-01'::date, '2026-01-01'::date,
     jsonb_build_object(
         'benzine', '(CO2*9 - 768)/12 * 1.5948',
         'diesel', '(CO2*9 - 600)/12 * 1.5948',
         'multiplier_post_2023_07', 2.75,
         'indexcoefficient', 1.5948
     ),
     106::smallint, 37.33::numeric(18, 4), 1.5948::numeric(12, 8),
     'https://www.acerta.be/nl/inspiratie/co2-bijdrage-bedrijfswagen-indexatie-en-wijzigingen-vanaf-1-januari-2025',
     'Acerta 2025: CO2 bijdrage geïndexeerd 1.5948, multiplier 2.75 post-2023-07'),
    ('2026-01-01'::date, null,
     jsonb_build_object(
         'benzine', '(CO2*9 - 768)/12 * 1.6291',
         'diesel', '(CO2*9 - 600)/12 * 1.6291',
         'multiplier_post_2023_07', 4.0,
         'indexcoefficient', 1.6291,
         'onbekende_co2_benzine_maand', 118.11,
         'onbekende_co2_diesel_maand', 120.15
     ),
     106::smallint, 42.34::numeric(18, 4), 1.6291::numeric(12, 8),
     'https://www.securex.be/nl/lex4you/werkgever/nieuws/bedrijfswagen-de-solidariteitsbijdrage-voor-2026-is-gekend',
     'Securex 2026: multiplier verhoogd 2.75 → 4.0, indexcoef 1.6291, min bijdrage €42.34')
on conflict do nothing;


-- ================================================================
-- 5. param_bijzondere_bijdragen — FSO update 2026-01-01
-- ================================================================
-- FSO klassiek: 0.17% → 0.32% (<20 wn), 0.22% → 0.37% (≥20 wn)
-- FSO tijdelijke werkloosheid: 0.16% → 0.09%
update public.param_bijzondere_bijdragen
    set geldig_tot = '2025-01-01'
    where geldig_van = '2024-01-01' and geldig_tot is null and type in ('fso', 'bev', 'asbest');

insert into public.param_bijzondere_bijdragen (
    type, geldig_van, geldig_tot,
    tarief, formule_json,
    bron_url, bron_document
) values
    -- 2025: onveranderd t.o.v. 2024 baseline
    ('fso', '2025-01-01'::date, '2026-01-01'::date, 0.0017::numeric(6, 4),
     jsonb_build_object('scope', 'klassiek <20 werknemers', 'incl_loonmatiging', 0.0018),
     'https://www.prato.be/werkgeversbijdragen-2025-verhoging-bijdragen-fonds-sluiting-ondernemingen/',
     'Prato 2025: FSO klassiek 0.17% <20wn'),
    ('bev', '2025-01-01'::date, '2026-01-01'::date, 0.0005::numeric(6, 4),
     '{}'::jsonb,
     'https://www.socialsecurity.be/employer/instructions/dmfa/nl/latest',
     '[POC_UNVERIFIED_2025] BEV — regionaal beheerd sinds 2015'),
    ('asbest', '2025-01-01'::date, '2026-01-01'::date, 0.0001::numeric(6, 4),
     '{}'::jsonb,
     'https://www.prato.be/werkgeversbijdragen-2025-verhoging-bijdragen-fonds-sluiting-ondernemingen/',
     'Prato 2025: asbest fonds 0.01% Q1-Q2'),

    -- 2026: FSO verhoogd
    ('fso', '2026-01-01'::date, null, 0.0032::numeric(6, 4),
     jsonb_build_object(
         'scope_klassiek_klein', 0.0032, 'scope_klassiek_groot', 0.0037,
         'scope_tijdelijke_werkloosheid', 0.0009, 'scope_niet_industrieel', 0.0001
     ),
     'https://www.besox.be/bijdragen-fonds-sluiting-ondernemingen/',
     'besox 2026: FSO klassiek verhoogd van 0.17% naar 0.32% <20wn'),
    ('bev', '2026-01-01'::date, null, 0.0005::numeric(6, 4),
     '{}'::jsonb,
     'https://www.socialsecurity.be/employer/instructions/dmfa/nl/latest',
     '[POC_PROJECTED_2026] BEV — geen wijziging aangekondigd'),
    ('asbest', '2026-01-01'::date, null, 0.0001::numeric(6, 4),
     '{}'::jsonb,
     'https://www.besox.be/bijdragen-fonds-sluiting-ondernemingen/',
     'besox 2026: asbest fonds 0.01% Q1-Q3')
on conflict do nothing;


-- ================================================================
-- 6. param_extralegaal — maaltijdcheque 6.91 → 8.91 per 2026-01-01
-- ================================================================
update public.param_extralegaal
    set geldig_tot = '2025-01-01'
    where geldig_van = '2024-01-01' and geldig_tot is null and voordeeltype = 'maaltijdcheque';

insert into public.param_extralegaal (
    voordeeltype, geldig_van, geldig_tot,
    max_wg, taks_pct,
    bron_url, bron_document
) values
    ('maaltijdcheque', '2025-01-01'::date, '2026-01-01'::date,
     6.91::numeric(18, 4), 0::numeric(6, 4),
     'https://www.attentia.be/nl/nieuws/verhoging-maaltijdcheques-vanaf-1-januari-2026/',
     'Attentia 2025: maaltijdcheque max werkgever €6.91/dag, RSZ+fiscaal vrij bij max'),
    ('maaltijdcheque', '2026-01-01'::date, null,
     8.91::numeric(18, 4), 0::numeric(6, 4),
     'https://www.attentia.be/nl/nieuws/verhoging-maaltijdcheques-vanaf-1-januari-2026/',
     'Attentia 2026-01-01: maaltijdcheque verhoogd €6.91 → €8.91 (regeerakkoord stap 1 naar €12)')
on conflict do nothing;


-- ================================================================
-- 7. param_doelgroepvermindering — Vlaanderen oudere-wn afgeschaft 2025-07-01
-- ================================================================
update public.param_doelgroepvermindering
    set geldig_tot = '2025-07-01',
        bron_document = coalesce(bron_document, '') || ' | 2025-07-01: volledig afgeschaft (LWB stopzetting)'
    where gewest = 'vlaanderen' and doelgroep = 'oudere_werknemer' and geldig_tot is null;


-- ================================================================
-- Post-migration diagnostiek
-- ================================================================
do $$
declare
    v_rsz_count int;
    v_struct_count int;
    v_plafond_count int;
begin
    select count(*) into v_rsz_count from public.param_rsz where geldig_van >= '2025-01-01';
    select count(*) into v_struct_count from public.param_structurele_vermindering where geldig_van >= '2025-04-01';
    select count(*) into v_plafond_count from public.param_plafond where geldig_van >= '2025-01-01';
    raise notice 'Fase 3 complete: param_rsz +% rijen, param_structurele +% rijen, param_plafond +% rijen (2025+2026)',
        v_rsz_count, v_struct_count, v_plafond_count;
end $$;
