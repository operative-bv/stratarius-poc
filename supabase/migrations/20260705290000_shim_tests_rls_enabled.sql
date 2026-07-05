-- ================================================================
-- Shim uitbreiding: tests.rls_enabled(text)
-- ================================================================
--
-- basejump upstream `tests.rls_enabled(schema_name)` — verifieert dat alle
-- tables in een schema RLS-enabled hebben. Test 01 gebruikt hem.
--
-- Return SETOF text produceert 1 pgtap `ok()` regel per call, matcht plan(N).
-- ================================================================

create or replace function tests.rls_enabled(testing_schema text)
    returns setof text
    language plpgsql
as $$
declare
    v_all_enabled boolean;
begin
    select bool_and(c.relrowsecurity) into v_all_enabled
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = testing_schema
      and c.relkind = 'r';
    return next ok(coalesce(v_all_enabled, false), format('RLS enabled on all tables in schema %I', testing_schema));
end;
$$;

grant execute on function tests.rls_enabled(text) to authenticated, postgres, service_role;
