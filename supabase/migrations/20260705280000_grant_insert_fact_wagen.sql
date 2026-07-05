-- ================================================================
-- fact_wagen: INSERT grant naar authenticated (consistency met andere fact_*)
-- ================================================================
--
-- fact_looncomponent en fact_prestatie hebben al INSERT grant naar authenticated
-- (via 20260703350000 fix_domain_table_grants of vergelijkbare migratie).
-- fact_wagen niet — mismatch. UI-flows die wagen-info toevoegen (bijv. bij
-- contract creation of via ad-hoc simulator) zullen 42501 raken.
--
-- Gedetecteerd via pgTAP test 39 refactor (ISS-085). RLS filter op contract_id
-- (via dim_contract FK → dim_legale_entiteit → owning_account_id) beperkt tot
-- caller's eigen tenants.
-- ================================================================

grant insert, update, delete on public.fact_wagen to authenticated;
