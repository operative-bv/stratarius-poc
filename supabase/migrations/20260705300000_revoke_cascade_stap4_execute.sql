-- ================================================================
-- ISS-087: REVOKE EXECUTE op cascade_stap4_doelgroepverminderingen
-- ================================================================
--
-- ISS-086 herstelde de column-REVOKE op dim_persoon.geslacht/opleidingsniveau.
-- 20260705270000 maakte cascade_populatie_snapshot SECURITY DEFINER met audit.
-- Nu de escape-hatch sluiten: cascade_stap4_doelgroepverminderingen (SECURITY
-- INVOKER, leest dim_persoon.opleidingsniveau direct) mag niet meer callable
-- zijn vanuit authenticated context. Enige valide pad is via de audit-gated
-- entry-RPC cascade_populatie_snapshot.
--
-- Andere cascade_stap* functies blijven callable — ze zijn pure math zonder
-- protected column access:
-- - stap2_basis_patronale_rsz, stap3_structurele_vermindering, stap5_bijzondere,
--   stap6_vakantiegeld, stap6b_eindejaarspremie, stap7_extralegaal,
--   stap8_wagen_solidariteitsbijdrage, stap9_arbeidsongevallen
--
-- Simulator page (src/app/dashboard/.../simulator/page.tsx) roept stap 2/3/5/6
-- direct aan. Die blijven werken.
--
-- Voor de facto: authenticated kon stap 4 al niet aanroepen (SECURITY INVOKER
-- + dim_persoon column-REVOKE zou 42501 geven). Deze migratie maakt dat
-- architecturaal ipv incidenteel — GDPR-intent is nu structuur ipv policy.
-- ================================================================

revoke execute on function public.cascade_stap4_doelgroepverminderingen(uuid, numeric, numeric, date)
    from authenticated;

comment on function public.cascade_stap4_doelgroepverminderingen(uuid, numeric, numeric, date) is
    'Doelgroepverminderingen JSONB rule engine. NIET direct aanroepbaar door authenticated (ISS-087) — GDPR-protected dim_persoon columns worden gelezen. Enige valide entry: cascade_populatie_snapshot RPC met audit-log.';
