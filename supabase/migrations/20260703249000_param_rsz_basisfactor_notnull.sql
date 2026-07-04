-- ================================================================
-- T-041 HOTFIX: param_rsz.basisfactor_pct NOT NULL
-- ================================================================
--
-- Fold uit T-026 plan-review round 1 (2026-07-03):
--   Origineel schema (T-015) had conditional CHECK:
--     ((status = 'bediende' and basisfactor_pct is null)
--      or (status = 'arbeider' and basisfactor_pct is not null))
--   Dit dwong cascade functies om coalesce(basisfactor, 1.0000) te doen — Principe II
--   inbreuk: branching op status in code. Data-driven oplossing: bediende rows krijgen
--   basisfactor = 1.0000 (by-convention, wiskundig identiek aan multiply-by-one),
--   conditional CHECK vervalt, NOT NULL wordt afgedwongen.
--
-- Single-purpose migration (fold clean-code MAJOR "separation of concerns"):
--   Dit bestand doet ALLEEN de schema HOTFIX. De cascade_stap2_basis_patronale_rsz
--   function komt in 20260703250000_cascade_stap2_basis_patronale_rsz.sql.
--
-- LOCK TABLE ACCESS EXCLUSIVE (fold security MINOR "toctou"):
--   Voorkomt concurrent INSERT van bediende row met NULL factor tussen DROP CHECK
--   en SET NOT NULL — die zou de SET NOT NULL doen falen.
--
-- Rollback (verbatim, fold error-handling MINOR "rollback-completeness"):
--   begin;
--   lock table public.param_rsz in access exclusive mode;
--   alter table public.param_rsz alter column basisfactor_pct drop not null;
--   update public.param_rsz set basisfactor_pct = null where status = 'bediende';
--   alter table public.param_rsz add constraint param_rsz_check1 check (
--       (status = 'bediende' and basisfactor_pct is null)
--       or (status = 'arbeider' and basisfactor_pct is not null)
--   );
--   commit;

begin;

lock table public.param_rsz in access exclusive mode;

alter table public.param_rsz drop constraint param_rsz_check1;

update public.param_rsz
    set basisfactor_pct = 1.0000
    where status = 'bediende'
      and basisfactor_pct is null;

alter table public.param_rsz
    alter column basisfactor_pct set not null;

commit;
