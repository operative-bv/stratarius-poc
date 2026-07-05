-- ================================================================
-- Shim uitbreiding: tests.create_supabase_user(identifier, email)
-- ================================================================
--
-- Basejump upstream heeft twee overloads voor create_supabase_user:
--   (identifier text) — deprecated
--   (identifier text, email text) — nieuwe signature
--
-- Onze shim (20260704001500) had alleen de 1-arg variant. Test 02
-- gebruikt de 2-arg. Deze migratie voegt de overload toe.
-- ================================================================

create or replace function tests.create_supabase_user(p_identifier text, p_email text)
    returns uuid
    language plpgsql
    security definer
    set search_path = auth, pg_catalog, pg_temp
as $$
declare
    v_user_id uuid;
begin
    v_user_id := (
        substring(md5(p_identifier), 1, 8) || '-' ||
        substring(md5(p_identifier), 9, 4) || '-' ||
        substring(md5(p_identifier), 13, 4) || '-' ||
        substring(md5(p_identifier), 17, 4) || '-' ||
        substring(md5(p_identifier), 21, 12)
    )::uuid;

    insert into auth.users (
        instance_id, id, aud, role, email,
        email_confirmed_at,
        created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data,
        is_super_admin, is_sso_user,
        confirmation_token, recovery_token,
        email_change_token_new, email_change,
        phone_change, phone_change_token,
        email_change_token_current, reauthentication_token
    )
    values (
        '00000000-0000-0000-0000-000000000000'::uuid,
        v_user_id,
        'authenticated', 'authenticated',
        p_email,
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{}'::jsonb,
        false, false,
        '', '', '', '', '', '', '', ''
    )
    on conflict (id) do nothing;

    return v_user_id;
end;
$$;

grant execute on function tests.create_supabase_user(text, text) to authenticated, postgres, service_role;


-- ================================================================
-- tests.authenticate_as_service_role() — basejump upstream helper
-- ================================================================
-- Onze shim (20260704001500) had deze niet. Test 11 gebruikt hem.

create or replace function tests.authenticate_as_service_role()
    returns void
    language plpgsql
as $$
begin
    perform set_config('role', 'service_role', true);
    perform set_config('request.jwt.claims', null, true);
end;
$$;

grant execute on function tests.authenticate_as_service_role() to authenticated, postgres, service_role;
