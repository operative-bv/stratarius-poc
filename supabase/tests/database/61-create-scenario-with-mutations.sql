BEGIN;
-- T-057: create_scenario_with_mutations RPC — unified scenario mutator.
--        Combineert loon-mutatie + wagen + extralegaal in één call via jsonb array.

create extension if not exists pgtap;

-- ISS-088: RPC is nu SECURITY DEFINER met auth.uid() + has_role_on_account check.
-- Set JWT claim direct naar Demo BVBA's seed owner uid (patroon uit test 63).
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims',
    json_build_object('sub','a0000000-0000-0000-0000-000000000001','role','authenticated')::text, true);

select plan(6);

-- Helper: temp table voor scenario-IDs die we tijdens de test aanmaken.
create temp table _t057_scenarios (label text primary key, scenario_id uuid);
create temp table _t057_baseline_stats (label text primary key, val numeric);

-- Baseline stats vastleggen (voor T2/T4).
insert into _t057_baseline_stats values ('avg_basisloon', (
    select avg(fl.bedrag)
    from public.fact_looncomponent fl
    join public.dim_looncomponent dl on dl.component_id = fl.component_id
    where fl.scenario_id = '11111111-1111-1111-1111-111111111111'::uuid
      and fl.periode = '2024-06-01'::date
      and dl.is_basisloon
));


------------------------------------------------------------
-- T1: Function existence
------------------------------------------------------------

select has_function(
    'public', 'create_scenario_with_mutations',
    array['uuid', 'text', 'uuid', 'date', 'jsonb'],
    'T1: create_scenario_with_mutations(uuid, text, uuid, date, jsonb) function exists'
);


------------------------------------------------------------
-- Setup T2: single mutation loon_pct_increase 5%
------------------------------------------------------------

insert into _t057_scenarios values ('t2_loon_only',
    public.create_scenario_with_mutations(
        'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
        'T057 test +5% loon',
        '11111111-1111-1111-1111-111111111111'::uuid,
        '2024-06-01'::date,
        '[{"type":"loon_pct_increase","value":5.0}]'::jsonb
    )
);

select is(
    round(
        (select avg(fl.bedrag)
         from public.fact_looncomponent fl
         join public.dim_looncomponent dl on dl.component_id = fl.component_id
         where fl.scenario_id = (select scenario_id from _t057_scenarios where label = 't2_loon_only')
           and fl.periode = '2024-06-01'::date
           and dl.is_basisloon)
        / (select val from _t057_baseline_stats where label = 'avg_basisloon'),
        4
    )::numeric,
    1.0500::numeric,
    'T2 loon_pct_increase 5%: new / baseline = 1.05 (bewijst mutation applied op basisloon)'
);


------------------------------------------------------------
-- Setup T3: wagen_add electric voor eerste functie in Demo BVBA
------------------------------------------------------------

insert into _t057_scenarios values ('t3_wagen_only',
    public.create_scenario_with_mutations(
        'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
        'T057 test wagen electric',
        '11111111-1111-1111-1111-111111111111'::uuid,
        '2024-06-01'::date,
        format('[{"type":"wagen_add","wagen_categorie":"electric","filter":{"functie_ids":["%s"]}}]',
            (select functie_id from public.dim_functie where owning_account_id = 'a1111111-1111-1111-1111-111111111111'::uuid limit 1)
        )::jsonb
    )
);

select cmp_ok(
    (select count(*)::int
     from public.fact_looncomponent fl
     where fl.scenario_id = (select scenario_id from _t057_scenarios where label = 't3_wagen_only')
       and fl.component_id = 'bedrijfswagen_tco'
       and fl.periode = '2024-06-01'::date),
    '>', 0::int,
    'T3 wagen_add: bedrijfswagen_tco componenten gecreëerd voor filtered contracten'
);


------------------------------------------------------------
-- Setup T4: combined loon +5% + wagen electric in één call
------------------------------------------------------------

insert into _t057_scenarios values ('t4_combined',
    public.create_scenario_with_mutations(
        'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
        'T057 test combined',
        '11111111-1111-1111-1111-111111111111'::uuid,
        '2024-06-01'::date,
        format('[{"type":"loon_pct_increase","value":5.0},{"type":"wagen_add","wagen_categorie":"electric","filter":{"functie_ids":["%s"]}}]',
            (select functie_id from public.dim_functie where owning_account_id = 'a1111111-1111-1111-1111-111111111111'::uuid limit 1)
        )::jsonb
    )
);

select ok(
    round(
        (select avg(fl.bedrag) from public.fact_looncomponent fl
         join public.dim_looncomponent dl on dl.component_id = fl.component_id
         where fl.scenario_id = (select scenario_id from _t057_scenarios where label = 't4_combined')
           and fl.periode = '2024-06-01'::date
           and dl.is_basisloon)
        / (select val from _t057_baseline_stats where label = 'avg_basisloon'), 4
    ) = 1.0500
    and
    (select count(*) from public.fact_looncomponent fl
     where fl.scenario_id = (select scenario_id from _t057_scenarios where label = 't4_combined')
       and fl.component_id = 'bedrijfswagen_tco'
       and fl.periode = '2024-06-01'::date) > 0,
    'T4 combined: loon +5% EN wagen electric samen — beide mutations applied'
);


------------------------------------------------------------
-- T5: Onbekend mutation type raise-t exception 22023
------------------------------------------------------------

select throws_ok(
    $$select public.create_scenario_with_mutations(
        'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
        'T057 invalid',
        '11111111-1111-1111-1111-111111111111'::uuid,
        '2024-06-01'::date,
        '[{"type":"nonexistent_type"}]'::jsonb
    )$$,
    '22023',
    NULL,
    'T5 onbekende mutation type raise-t 22023 (invalid_parameter_value)'
);


------------------------------------------------------------
-- T6: Lege mutations array raise-t exception 22023
------------------------------------------------------------

select throws_ok(
    $$select public.create_scenario_with_mutations(
        'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
        'T057 empty',
        '11111111-1111-1111-1111-111111111111'::uuid,
        '2024-06-01'::date,
        '[]'::jsonb
    )$$,
    '22023',
    NULL,
    'T6 lege mutations array raise-t 22023'
);


select * from finish();
ROLLBACK;
