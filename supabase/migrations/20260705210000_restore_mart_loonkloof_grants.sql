-- ================================================================
-- Restore mart_loonkloof grants na drop-cascade in 20260705170000
-- ================================================================
--
-- Migratie 20260705170000 dropte mart_loonkloof CASCADE om kwartaal_eindes
-- uit te breiden tot 2026-Q4, maar herstelde niet de `grant select on
-- public.mart_loonkloof to authenticated` uit 20260703350000.
--
-- Gevolg: authenticated users kregen "permission denied for materialized
-- view mart_loonkloof" bij directe SELECTs (loonkloof/page.tsx, oaxaca).
-- Gedetecteerd via pgTAP test 65 na ISS-084 shim-fix (die de test
-- daadwerkelijk als authenticated laat draaien).
--
-- Prod-impact: gemaskeerd zolang bestaande materialized view uit
-- 20260703310000 nog leefde. Op nieuwe environments (die 20260705170000
-- doorlopen) breekt de UI stil zonder deze grant.
--
-- Zelfde bug bij mart_loonkloof_decomp_read: 20260704001350 dropt de
-- function cascade, 20260705180000 recreate zonder grant execute. Prod
-- werkt momenteel omdat de function daar nog met oude grant leeft, maar
-- op elke nieuwe env is de RPC unreachable voor authenticated → oaxaca
-- laadt niet.
-- ================================================================

grant select on public.mart_loonkloof to authenticated;

revoke execute on function public.mart_loonkloof_decomp_read(text, uuid, text) from public;
grant execute on function public.mart_loonkloof_decomp_read(text, uuid, text) to authenticated;
