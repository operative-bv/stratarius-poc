-- ================================================================
-- service_role: EXECUTE grant op public helper functies
-- ================================================================
--
-- Gedetecteerd via pgTAP test 11: `current_user_account_role` had geen
-- execute grant voor service_role. Vergelijkbaar met eerdere sessie-vondsten
-- waar service_role grants systematisch ontbraken.
--
-- Blast radius klein: service_role is admin/backend-only role, geen prod
-- feature depends on this. Maar backend scripts die geset_account /
-- current_user_account_role aanroepen zouden falen.
-- ================================================================

grant execute on function public.get_account(uuid) to service_role;
grant execute on function public.get_account_by_slug(text) to service_role;
grant execute on function public.current_user_account_role(uuid) to service_role;
grant execute on function public.get_accounts() to service_role;
grant execute on function public.get_personal_account() to service_role;
grant execute on function public.update_account(uuid, text, text, jsonb, boolean) to service_role;
