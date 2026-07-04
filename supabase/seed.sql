-- Demo seed: user + tenant + 4 teams × 5-10 mensen elk
-- Login: test@stratarius.local / test1234
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_super_admin)
VALUES ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'test@stratarius.local', crypt('test1234', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), FALSE)
ON CONFLICT (id) DO NOTHING;

-- auth.identities row is verplicht voor password-login (anders 'could not authenticate user')
INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    jsonb_build_object('sub', 'a0000000-0000-0000-0000-000000000001', 'email', 'test@stratarius.local', 'email_verified', true),
    'email',
    now(),
    now(),
    now()
)
ON CONFLICT (provider_id, provider) DO NOTHING;
INSERT INTO basejump.accounts (id, name, slug, personal_account, primary_owner_user_id) VALUES ('a1111111-1111-1111-1111-111111111111', 'Demo BVBA', 'demo-bvba', false, 'a0000000-0000-0000-0000-000000000001');
INSERT INTO basejump.account_user (account_id, user_id, account_role) VALUES ('a1111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'owner');
INSERT INTO public.dim_legale_entiteit (legale_entiteit_id, owning_account_id, werkgeverscategorie, naam, land_id, gewest) VALUES ('aaaaaaaa-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 1, 'Demo BVBA', 'BE', 'vlaanderen');

-- 4 teams (functies)
INSERT INTO public.dim_functie (functie_id, owning_account_id, functienaam, functieniveau) VALUES
    ('f1000000-0000-0000-0000-000000000001', 'a1111111-1111-1111-1111-111111111111', 'Sales', 12),
    ('f1000000-0000-0000-0000-000000000002', 'a1111111-1111-1111-1111-111111111111', 'Engineering', 18),
    ('f1000000-0000-0000-0000-000000000003', 'a1111111-1111-1111-1111-111111111111', 'Operations', 10),
    ('f1000000-0000-0000-0000-000000000004', 'a1111111-1111-1111-1111-111111111111', 'Management', 25);

INSERT INTO public.dim_scenario (scenario_id, legale_entiteit_id, naam, kind) VALUES
    ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-1111-1111-1111-111111111111', 'Baseline 2024', 'baseline'),
    ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-1111-1111-1111-111111111111', '+5% loonsverhoging', 'what_if'),
    ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-1111-1111-1111-111111111111', 'Sales team +€200 basisloon', 'what_if');

DO $DEMO$
DECLARE
    team_uuids uuid[] := ARRAY['f1000000-0000-0000-0000-000000000001'::uuid, 'f1000000-0000-0000-0000-000000000002'::uuid, 'f1000000-0000-0000-0000-000000000003'::uuid, 'f1000000-0000-0000-0000-000000000004'::uuid];
    team_sizes int[] := ARRAY[10, 8, 6, 3];  -- 10 sales, 8 eng, 6 ops, 3 management = 27 total
    team_base_bruto numeric[] := ARRAY[3200, 4500, 2900, 6500];
    ti int; pi int;
    persoon_uuid uuid;
    contract_uuid uuid;
    bruto_val numeric;
    stat text;
    is_sales bool;
BEGIN
    FOR ti IN 1..array_length(team_uuids, 1) LOOP
        FOR pi IN 1..team_sizes[ti] LOOP
            persoon_uuid := gen_random_uuid();
            contract_uuid := gen_random_uuid();
            bruto_val := team_base_bruto[ti] + (pi * 150);  -- variatie binnen team
            stat := CASE WHEN ti = 3 AND pi % 2 = 0 THEN 'arbeider' ELSE 'bediende' END;  -- Ops heeft arbeiders
            is_sales := ti = 1;

            INSERT INTO public.dim_persoon (persoon_id, owning_account_id, geslacht, geboortedatum, opleidingsniveau)
            VALUES (persoon_uuid, 'a1111111-1111-1111-1111-111111111111',
                    CASE WHEN pi % 2 = 0 THEN 'v' ELSE 'm' END,
                    (date '1975-01-01' + (pi * interval '1 year'))::date,
                    CASE WHEN ti = 2 OR ti = 4 THEN 'hooggeschoold' ELSE 'middel_geschoold' END);

            INSERT INTO public.dim_contract (contract_id, persoon_id, legale_entiteit_id, functie_id, pc_id, status, fte_breuk, geldig_van)
            VALUES (contract_uuid, persoon_uuid, 'aaaaaaaa-1111-1111-1111-111111111111', team_uuids[ti],
                    CASE WHEN stat = 'arbeider' THEN '124' ELSE '200' END,
                    stat, 1.0000, '2023-01-01');

            -- Baseline
            INSERT INTO public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag)
            VALUES (contract_uuid, '2024-06-01', 'basisloon', '11111111-1111-1111-1111-111111111111', bruto_val);

            -- +5% scenario
            INSERT INTO public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag)
            VALUES (contract_uuid, '2024-06-01', 'basisloon', '22222222-2222-2222-2222-222222222222', bruto_val * 1.05);

            -- Sales +€200 scenario: sales team krijgt +200, anderen baseline
            INSERT INTO public.fact_looncomponent (contract_id, periode, component_id, scenario_id, bedrag)
            VALUES (contract_uuid, '2024-06-01', 'basisloon', '33333333-3333-3333-3333-333333333333',
                    CASE WHEN is_sales THEN bruto_val + 200 ELSE bruto_val END);
        END LOOP;
    END LOOP;
END $DEMO$;

SELECT 'Setup:' as status;
SELECT functienaam, count(*) as headcount FROM dim_contract c JOIN dim_functie f ON f.functie_id = c.functie_id GROUP BY functienaam;
