-- ================================================================
-- Fix param_structurele_vermindering drift op prod
-- ================================================================
--
-- De vorige diagnostic-migration (20260705090000) toonde in de push-
-- output dat prod de VERKEERDE waarden heeft voor cat 1:
--
--   Prod (verkeerd):  gamma=0.00,  S0=7207.20,  S1=12435.31
--   Local (correct):  gamma=0.40,  S0=10797.67, S1=6807.18
--
-- Gevolg: bij bruto €2500 (kwartaal S=7500) is S > S0 dus de lage-
-- lonen tak geeft 0, en gamma=0 dus de zeer-lage-lonen tak ook 0.
-- Vermindering = 0 voor alle contracten, ook lage-lonen.
--
-- Wortelke: edit-in-place op de originele import migration + hotfix
-- migrations. Prod kreeg alleen de eerste versie, local heeft alle
-- hotfixes gecumuleerd via `db reset`.
--
-- Deze migration UPDATE de waarden naar de 2024-correcte versie.
-- Idempotent: als de waarden al kloppen doet de update effectief niets
-- (kolommen gelijk gezet aan zelfde waarden).
-- ================================================================

update public.param_structurele_vermindering
set forfait        = 0.0000,
    coefficient_a  = 0.14000000,
    coefficient_b  = 0.40000000,
    drempel_s0     = 10797.6700,
    drempel_s1     = 6807.1800
where werkgeverscategorie = 1
  and geldig_van = '2024-01-01'::date;

update public.param_structurele_vermindering
set forfait        = 49.0000,
    coefficient_a  = 0.26410000,
    coefficient_b  = 0.00000000,
    drempel_s0     = 7207.2000,
    drempel_s1     = 6807.1800
where werkgeverscategorie = 2
  and geldig_van = '2024-01-01'::date;

update public.param_structurele_vermindering
set forfait        = 375.0000,
    coefficient_a  = 0.17140000,
    coefficient_b  = 0.00000000,
    drempel_s0     = 7207.2000,
    drempel_s1     = 6807.1800
where werkgeverscategorie = 3
  and geldig_van = '2024-01-01'::date;

-- Post-update verificatie
do $$
declare
    r record;
begin
    for r in
        select werkgeverscategorie, forfait, coefficient_a, coefficient_b, drempel_s0, drempel_s1
        from public.param_structurele_vermindering
        where '2024-06-30'::date >= geldig_van
          and (geldig_tot is null or '2024-06-30'::date < geldig_tot)
        order by werkgeverscategorie
    loop
        raise notice 'Post-update cat %: alpha=%, gamma=%, S0=%, S1=%',
            r.werkgeverscategorie, r.coefficient_a, r.coefficient_b, r.drempel_s0, r.drempel_s1;
    end loop;
end $$;
