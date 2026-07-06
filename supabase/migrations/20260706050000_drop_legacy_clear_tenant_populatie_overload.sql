-- ================================================================
-- Drop legacy clear_tenant_populatie overload
-- ================================================================
-- Migration 20260706040000 herdefinieerde clear_tenant_populatie met
-- signature (p_legale_entiteit_id uuid), maar de oude 2-arg versie
-- (p_legale_entiteit_id uuid, p_rechtsgrondslag text default ...) uit
-- 20260705140000 werd door create-or-replace niet vervangen (andere
-- signature = nieuwe functie ernaast). PostgREST kan nu niet kiezen
-- welke overload aan te roepen → PGRST203 "Could not choose the best
-- candidate function between".
--
-- De oude versie referenceert fact_loonkost die in 20260706030000 is
-- gedropt, dus deze functie zou sowieso runtime-error geven bij een
-- call. Veiliger + schoner om te droppen.
-- ================================================================

drop function if exists public.clear_tenant_populatie(uuid, text);

comment on function public.clear_tenant_populatie(uuid) is
    'Wist alle populatie-data (dim_persoon + dim_contract + fact_*) voor gegeven legale entiteit. '
    'SECURITY DEFINER met has_role_on_account tenant-check en resiliente gdpr_access_log audit. '
    'Invalideert mart_populatie_loonkost en mart_loonkloof caches per tenant.';
