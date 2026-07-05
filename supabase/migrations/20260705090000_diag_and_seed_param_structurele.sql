-- ================================================================
-- Diagnostiek + safety seed voor param_structurele_vermindering
-- ================================================================
--
-- Symptoom in productie: stap3_vermindering = €0 voor alle contracten,
-- ook lage-lonen (bruto €2500 waarbij formule ~€190/maand zou geven).
--
-- Hypothese: param_structurele_vermindering niet geseed op prod
-- (migration 20260703150000_import_rsz_structurele_doelgroep_2024
-- staat wel als applied maar mogelijk deels gefaald zoals de eerdere
-- drift saga). Function → NULL → coalesce → 0.
--
-- Deze migration:
--   1. Raise notices met huidige state (aantal actieve rijen, waarden)
--   2. Seed cat 1 als niet aanwezig (correcte 2024 waarden)
--   3. Idempotent op local (WHERE NOT EXISTS) — geen dubbele rijen
-- ================================================================

do $$
declare
    v_count int;
    r record;
begin
    -- Diagnostiek: totaal aantal rijen
    select count(*) into v_count from public.param_structurele_vermindering;
    raise notice 'param_structurele_vermindering: % totaal rijen', v_count;

    -- Actieve rijen op 2024-06-30 (de datum die de UI default gebruikt)
    for r in
        select werkgeverscategorie, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1
        from public.param_structurele_vermindering
        where '2024-06-30'::date >= geldig_van
          and (geldig_tot is null or '2024-06-30'::date < geldig_tot)
        order by werkgeverscategorie
    loop
        raise notice 'Actief op 2024-06-30 — cat %: F=%, alpha=%, gamma=%, S0=%, S1=%',
            r.werkgeverscategorie, r.forfait, r.coefficient_a, r.coefficient_b, r.drempel_s0, r.drempel_s1;
    end loop;
end $$;

-- Seed cat 1, 2, 3 met correcte 2024 waarden — alleen als niet aanwezig.
insert into public.param_structurele_vermindering (
    werkgeverscategorie, geldig_van, geldig_tot,
    forfait, coefficient_a, coefficient_b,
    drempel_s0, drempel_s1,
    bron_url, bron_document
)
select v.werkgeverscategorie, v.geldig_van, v.geldig_tot,
       v.forfait, v.coefficient_a, v.coefficient_b,
       v.drempel_s0, v.drempel_s1,
       v.bron_url, v.bron_document
from (values
    (1::smallint, '2024-01-01'::date, '2025-01-01'::date,
     0.0000::numeric(18,4), 0.14000000::numeric(12,8), 0.40000000::numeric(12,8),
     10797.67::numeric(18,4), 6807.18::numeric(18,4),
     'https://www.socialsecurity.be/employer/instructions/'::text,
     'RSZ instructiegids 1 april 2024 — cat 1 (seed via drift-repair fix)'::text),
    (2::smallint, '2024-01-01'::date, '2025-01-01'::date,
     49.0000::numeric(18,4), 0.26410000::numeric(12,8), 0.00000000::numeric(12,8),
     7207.20::numeric(18,4), 6807.18::numeric(18,4),
     'https://www.socialsecurity.be/employer/instructions/'::text,
     '[POC_UNVERIFIED_2024] cat 2 social profit (seed via drift-repair fix)'::text),
    (3::smallint, '2024-01-01'::date, '2025-01-01'::date,
     375.0000::numeric(18,4), 0.17140000::numeric(12,8), 0.00000000::numeric(12,8),
     7207.20::numeric(18,4), 6807.18::numeric(18,4),
     'https://www.socialsecurity.be/employer/instructions/'::text,
     '[POC_UNVERIFIED_2024] cat 3 beschutte werkplaats (seed via drift-repair fix)'::text)
) as v(werkgeverscategorie, geldig_van, geldig_tot,
       forfait, coefficient_a, coefficient_b,
       drempel_s0, drempel_s1,
       bron_url, bron_document)
where not exists (
    select 1 from public.param_structurele_vermindering t
    where t.werkgeverscategorie = v.werkgeverscategorie
      and t.geldig_van = v.geldig_van
);

-- Post-seed diagnostiek: hoeveel rijen zijn er nu?
do $$
declare
    v_count int;
begin
    select count(*) into v_count
    from public.param_structurele_vermindering
    where '2024-06-30'::date >= geldig_van
      and (geldig_tot is null or '2024-06-30'::date < geldig_tot);
    raise notice 'Na seed: % actieve rijen op 2024-06-30', v_count;
end $$;
