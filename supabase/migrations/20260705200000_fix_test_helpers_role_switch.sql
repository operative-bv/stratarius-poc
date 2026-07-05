-- ================================================================
-- ISS-084 fix: tests.authenticate_as doet ook role switch
-- ================================================================
--
-- Ontdekt tijdens pgTAP test 65-cross-tenant. De bestaande shim
-- (20260704001500) documenteerde dat callers zelf `SET LOCAL role
-- authenticated` moesten doen na tests.authenticate_as. In de praktijk
-- doet niemand dat, waardoor tests als postgres superuser runden en
-- RLS werd bypassed → false-negatives op tenant isolation asserts.
--
-- basejump upstream doet WEL de role switch:
--   https://github.com/usebasejump/supabase-test-helpers/blob/main/supabase-test-helpers/tests.sql
--
-- Deze migration aligned de shim met upstream. Bestaande tests die
-- rekende op postgres-context worden mogelijk rood — dat is een goed
-- teken (false-negatives worden zichtbaar).
-- ================================================================

create or replace function tests.authenticate_as(p_identifier text)
    returns void
    language plpgsql
as $$
declare
    v_user_id uuid;
    v_claims jsonb;
begin
    v_user_id := (
        substring(md5(p_identifier), 1, 8) || '-' ||
        substring(md5(p_identifier), 9, 4) || '-' ||
        substring(md5(p_identifier), 13, 4) || '-' ||
        substring(md5(p_identifier), 17, 4) || '-' ||
        substring(md5(p_identifier), 21, 12)
    )::uuid;

    v_claims := jsonb_build_object(
        'sub',   v_user_id::text,
        'email', p_identifier || '@test.local',
        'role',  'authenticated',
        'aud',   'authenticated'
    );

    perform set_config('request.jwt.claims', v_claims::text, true);
    -- ISS-084: ook de role switch, matcht upstream basejump behavior.
    -- Zonder deze bleef de session als postgres draaien → RLS bypassed
    -- → tenant isolation assertions gaven false-positives.
    perform set_config('role', 'authenticated', true);
end;
$$;

-- clear_authentication moet consistent role terug resetten naar postgres
-- (test session default) — anders is next test in dezelfde suite als
-- authenticated user.

create or replace function tests.clear_authentication()
    returns void
    language plpgsql
as $$
begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('role', 'postgres', true);
end;
$$;
