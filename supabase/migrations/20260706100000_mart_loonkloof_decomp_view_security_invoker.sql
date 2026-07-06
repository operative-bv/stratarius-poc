-- ================================================================
-- ISS-093: mart_loonkloof_decomp view — security_invoker + REVOKE public
-- ================================================================
--
-- Claude Agent 3 #2 (92/100 confidence): view is aangemaakt zonder
-- WITH (security_invoker=true). Views draaien default als owner
-- (postgres = BYPASSRLS). Auth'd user die `select * from
-- mart_loonkloof_decomp` doet buiten de RPC om, krijgt rijen van
-- ALLE tenants. mart_loonkloof_decomp_read RPC bewaakt correct via
-- has_role_on_account, maar wie de view direct bevraagt omzeilt dat.
--
-- Fix (defense-in-depth, twee lagen):
-- 1. ALTER VIEW ... SET (security_invoker=true) — view respecteert
--    nu RLS van caller (Postgres 15+ ALTER-syntax, geen drop-recreate
--    nodig zoals bij oudere versies). mart_loonkloof onder de motorkap
--    heeft RLS-policy has_role_on_account, dus view returnt alleen
--    caller's tenant rijen.
-- 2. Expliciet REVOKE ALL FROM public + GRANT SELECT alleen aan
--    authenticated — voorkomt onbedoelde grants via public role.
-- ================================================================

alter view public.mart_loonkloof_decomp set (security_invoker = true);

comment on view public.mart_loonkloof_decomp is
    'ISS-093: view runt met security_invoker=true zodat RLS van mart_loonkloof + dim_persoon '
    'wordt gerespecteerd. Directe SELECT toont alleen caller''s tenant. '
    'mart_loonkloof_decomp_read RPC blijft de canonieke access-path (extra tenant-check + audit).';

revoke all on public.mart_loonkloof_decomp from public;
grant select on public.mart_loonkloof_decomp to authenticated;
