-- ================================================================
-- Grant EXECUTE op clear_tenant_populatie(uuid)
-- ================================================================
-- Migration 20260706040000 herdefinieerde clear_tenant_populatie met
-- nieuwe signature (p_legale_entiteit_id uuid), maar vergat GRANT
-- EXECUTE TO authenticated toe te voegen. De EXECUTE-grant op de
-- oude 2-arg overload (uit 20260705140000) dropte mee toen de oude
-- overload werd verwijderd in 20260706050000.
--
-- Manifesteerde als "Wissen faalde: permission denied for function
-- clear_tenant_populatie" bij aanroep vanuit de UI.
-- ================================================================

grant execute on function public.clear_tenant_populatie(uuid) to authenticated;
