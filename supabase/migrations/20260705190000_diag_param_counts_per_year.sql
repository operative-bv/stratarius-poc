-- ================================================================
-- Prod smoke verify: param_* rijen per jaar
-- ================================================================
--
-- Diagnostic RAISE NOTICE per param_* tabel om te bevestigen dat
-- fase 3 (2025+2026 imports) daadwerkelijk op prod aanwezig is.
-- Bij push output zie je direct aantallen per (tabel, jaar).
--
-- Deze migration muteert NIETS — puur notice-only. Draait op elke
-- environment (local + prod) hetzelfde.
-- ================================================================

do $$
declare
    v_rec record;
begin
    raise notice '=== param_* rijen per jaar ===';

    for v_rec in
        select
            'param_rsz' as tabel,
            extract(year from geldig_van)::int as jaar,
            count(*)::int as rijen
        from public.param_rsz group by extract(year from geldig_van)
        union all
        select
            'param_structurele_vermindering',
            extract(year from geldig_van)::int,
            count(*)::int
        from public.param_structurele_vermindering group by extract(year from geldig_van)
        union all
        select
            'param_plafond',
            extract(year from geldig_van)::int,
            count(*)::int
        from public.param_plafond group by extract(year from geldig_van)
        union all
        select
            'param_doelgroepvermindering',
            extract(year from geldig_van)::int,
            count(*)::int
        from public.param_doelgroepvermindering group by extract(year from geldig_van)
        union all
        select
            'param_wagen_mobiliteit',
            extract(year from geldig_van)::int,
            count(*)::int
        from public.param_wagen_mobiliteit group by extract(year from geldig_van)
        union all
        select
            'param_bijzondere_bijdragen',
            extract(year from geldig_van)::int,
            count(*)::int
        from public.param_bijzondere_bijdragen group by extract(year from geldig_van)
        union all
        select
            'param_extralegaal',
            extract(year from geldig_van)::int,
            count(*)::int
        from public.param_extralegaal group by extract(year from geldig_van)
        union all
        select
            'param_vakantiegeld',
            extract(year from geldig_van)::int,
            count(*)::int
        from public.param_vakantiegeld group by extract(year from geldig_van)
        order by 1, 2
    loop
        raise notice '  %  %  = % rijen', v_rec.tabel, v_rec.jaar, v_rec.rijen;
    end loop;

    raise notice '=== structurele vermindering — γ-shift per periode (cat 1) ===';

    for v_rec in
        select
            geldig_van::text as tabel,
            0 as jaar,
            0 as rijen,
            forfait,
            coefficient_a,
            coefficient_b as gamma,
            drempel_s0,
            drempel_s1
        from public.param_structurele_vermindering
        where werkgeverscategorie = 1
        order by geldig_van
    loop
        raise notice '  cat 1 geldig_van=%  F=% α=% γ=% S0=% S1=%',
            v_rec.tabel, v_rec.forfait, v_rec.coefficient_a, v_rec.gamma, v_rec.drempel_s0, v_rec.drempel_s1;
    end loop;
end $$;
