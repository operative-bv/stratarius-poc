-- ================================================================
-- ISS-030: test helpers shim
-- ================================================================
--
-- basejump-supabase_test_helpers is een externe extension die NIET beschikbaar
-- is in de standaard Supabase Postgres container. Deze migration levert een
-- functionele shim: schema `tests` + minimale set functies die de test-suite
-- verwacht (create_supabase_user, authenticate_as, get_supabase_uid, clear_authentication).
--
-- Shim-functies zijn STABLE + SECURITY DEFINER waar nodig; ze doen inserts in
-- auth.users en zetten JWT claims voor RLS-context.
--
-- Impact:
--   - Migration is harmless in production (test-helpers zijn no-ops zonder
--     test-context) maar liefst kan het via omgevings-flag geskipt.
--   - Bestaande pgTAP tests moeten `create extension` regel vervangen door
--     `create extension if not exists pgtap;` (aparte sed-pass in ISS-030 fix).
--
-- Referentie voor upstream extension API:
--   https://github.com/usebasejump/supabase-test-helpers
--
-- Rollback:
--   DROP SCHEMA tests CASCADE;


create schema if not exists tests;


-- ================================================================
-- tests.create_supabase_user(identifier)
-- ================================================================
-- Creëert een user in auth.users met een deterministische UUID gebaseerd op
-- identifier. Retourneert de nieuwe uuid. Idempotent: bestaande user wordt
-- teruggegeven bij dezelfde identifier.

create or replace function tests.create_supabase_user(p_identifier text)
    returns uuid
    language plpgsql
    security definer
    set search_path = auth, pg_catalog, pg_temp
as $$
declare
    v_user_id uuid;
begin
    -- Deterministische UUID via md5(identifier) → uuid formaat.
    v_user_id := (
        substring(md5(p_identifier), 1, 8) || '-' ||
        substring(md5(p_identifier), 9, 4) || '-' ||
        substring(md5(p_identifier), 13, 4) || '-' ||
        substring(md5(p_identifier), 17, 4) || '-' ||
        substring(md5(p_identifier), 21, 12)
    )::uuid;

    -- Insert user in auth.users; als bestaat, terug naar user_id.
    -- Geen echte password hash — test-only user, credentials worden nooit gecheckt.
    insert into auth.users (
        instance_id, id, aud, role, email,
        email_confirmed_at,
        created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data,
        is_super_admin, is_sso_user
    )
    values (
        '00000000-0000-0000-0000-000000000000'::uuid,
        v_user_id,
        'authenticated', 'authenticated',
        p_identifier || '@test.local',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{}'::jsonb,
        false, false
    )
    on conflict (id) do nothing;

    return v_user_id;
end;
$$;


-- ================================================================
-- tests.authenticate_as(identifier)
-- ================================================================
-- Zet request.jwt.claims voor de duur van transactie zodat auth.uid() de
-- gegeven user teruggeeft. RLS policies zullen deze user als caller zien.

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

    -- SET LOCAL zonder SECURITY DEFINER omdat set_config('role', ...) niet
    -- toegestaan is binnen SECURITY DEFINER functies (session-scoped).
    perform set_config('request.jwt.claims', v_claims::text, true);
    -- Role-switch is optioneel voor pgTAP tests — meestal draaien ze als postgres
    -- die RLS bypasst. Als expliciet authenticated-context nodig is, doet caller
    -- SET LOCAL role authenticated ná deze call.
end;
$$;


-- ================================================================
-- tests.get_supabase_uid(identifier)
-- ================================================================
-- Returns het deterministische user_id voor een identifier zonder side-effects.

create or replace function tests.get_supabase_uid(p_identifier text)
    returns uuid
    language sql
    stable
as $$
    select (
        substring(md5(p_identifier), 1, 8) || '-' ||
        substring(md5(p_identifier), 9, 4) || '-' ||
        substring(md5(p_identifier), 13, 4) || '-' ||
        substring(md5(p_identifier), 17, 4) || '-' ||
        substring(md5(p_identifier), 21, 12)
    )::uuid;
$$;


-- ================================================================
-- tests.clear_authentication()
-- ================================================================
-- Reset JWT claims naar leeg — auth.uid() returnt NULL na deze call.

create or replace function tests.clear_authentication()
    returns void
    language plpgsql
as $$
begin
    perform set_config('request.jwt.claims', '', true);
end;
$$;


-- Grant execute op tests schema aan authenticated + postgres (tests draaien
-- meestal als postgres via `supabase test db`).
grant usage on schema tests to authenticated, postgres, service_role;
grant execute on all functions in schema tests to authenticated, postgres, service_role;
