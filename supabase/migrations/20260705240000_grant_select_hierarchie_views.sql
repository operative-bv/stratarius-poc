-- ================================================================
-- Herstel SELECT grants op view_hierarchie_* views voor authenticated
-- ================================================================
--
-- 4 hierarchie views (statutair, business, geografisch, kostenplaats)
-- hebben géén SELECT grant voor authenticated. Waarschijnlijk gedropped
-- door een eerdere drop-cascade en niet hersteld — vergelijkbaar met
-- mart_loonkloof grants weggevallen bij drop cascade eerder deze sessie.
--
-- Gedetecteerd via pgTAP test 26 refactor (ISS-085).
-- ================================================================

grant select on public.view_hierarchie_statutair to authenticated;
grant select on public.view_hierarchie_business to authenticated;
grant select on public.view_hierarchie_geografisch to authenticated;
grant select on public.view_hierarchie_kostenplaats to authenticated;
