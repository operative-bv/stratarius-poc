-- ================================================================
-- T-041: cascade_stap2_basis_patronale_rsz pure functie
-- ================================================================
--
-- Constitution Principe III: pure SQL functie in de rekencascade. Berekent
-- basis patronale RSZ als grondslag × basisbijdrage_pct × basisfactor via
-- temporele join op param_rsz.
--
-- Principe II data-driven: tarief én factor uit param_rsz via
--   (status, werkgeverscategorie, periode) join. GEEN hardcoded 25.07% of 1.08.
--
-- Principe I effective-dating: temporele join met half-open interval
--   [geldig_van, geldig_tot) — geldig_van inclusief, geldig_tot exclusief.
--
-- Principe V TDD 2-commit: test-commit 2d280e2 (43a + 44) is EERDER dan deze migration.
--
-- Depends: T-041 HOTFIX (20260703249000_param_rsz_basisfactor_notnull.sql) —
--   basisfactor_pct is NOT NULL en bediende rows hebben 1.0000.
--
-- Formule:
--   basis_patronale_rsz = p_rsz_grondslag × pr.basisbijdrage_pct × pr.basisfactor_pct
--
-- NULL contract (consistent met T-023/T-024/T-026):
--   Temporele join miss (onbekende status/categorie/periode) → NULL.
--   Cascade orchestrator (T-029) detecteert NULL en throwt gestructureerde fout.
--   Documented decision in plan-review round 1 (contested error-handling MAJOR):
--   silent NULL patroon is consistent met sibling cascade functies. Alternatief
--   (plpgsql RAISE per function) zou 4 verschillende raise-paths creëren zonder
--   centrale error-handling logica.
--
-- Rollback:
--   DROP FUNCTION public.cascade_stap2_basis_patronale_rsz(numeric, text, smallint, date);


create or replace function public.cascade_stap2_basis_patronale_rsz(
    p_rsz_grondslag       numeric(18, 4),
    p_status              text,
    p_werkgeverscategorie smallint,
    p_periode             date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    select (
        p_rsz_grondslag
      * pr.basisbijdrage_pct
      * pr.basisfactor_pct
    )::numeric(18, 4)
    from public.param_rsz pr
    where pr.status               = p_status
      and pr.werkgeverscategorie  = p_werkgeverscategorie
      and p_periode              >= pr.geldig_van
      and (pr.geldig_tot is null or p_periode < pr.geldig_tot);
$$;

comment on function public.cascade_stap2_basis_patronale_rsz(numeric, text, smallint, date) is
    'Cascade stap 2: basis patronale RSZ = grondslag x basisbijdrage_pct x basisfactor_pct via temporele join op param_rsz. Principe II data-driven (tarief + factor uit param_rsz, geen hardcoded 25%). Principe I half-open interval [geldig_van, geldig_tot). NULL contract: temporele miss (onbekende status/categorie/periode) -> NULL; cascade orchestrator T-029 detecteert. LANGUAGE SQL STABLE PARALLEL SAFE met pinned search_path.';

grant execute on function public.cascade_stap2_basis_patronale_rsz(numeric, text, smallint, date) to authenticated;
