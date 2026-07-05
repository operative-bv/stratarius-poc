BEGIN;
-- T-051: create_simulator_scenario RPC — synthetic contract flow.
--   Creëert in één transactie: dim_persoon + dim_functie + dim_contract +
--   dim_scenario + fact_prestatie + fact_looncomponent, en roept vervolgens
--   create_populatie_loonkost aan om cascade output te persistent.

create extension if not exists pgtap;

select plan(6);

-- ISS-085: create_simulator_scenario roept intern cascade_populatie_snapshot aan
-- die nu SECURITY DEFINER is met auth.uid() check. Set JWT claim direct naar
-- Demo BVBA's seed owner uid — tests.authenticate_as gebruikt md5-based UUIDs
-- die niet matchen met a0000000-0000-0000-0000-000000000001 uit seed.
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims',
    json_build_object('sub','a0000000-0000-0000-0000-000000000001','role','authenticated')::text, true);


------------------------------------------------------------
-- T1: Function existence
------------------------------------------------------------

select has_function(
    'public', 'create_simulator_scenario',
    array['uuid', 'text', 'date', 'jsonb'],
    'T1: create_simulator_scenario(uuid, text, date, jsonb) function exists'
);


------------------------------------------------------------
-- Setup T2-T5: roep function aan met sample synthetic contract.
------------------------------------------------------------

create temp table _t051_scenarios (label text primary key, scenario_id uuid);

insert into _t051_scenarios values ('main',
    public.create_simulator_scenario(
        'aaaaaaaa-1111-1111-1111-111111111111'::uuid,
        'T051 test simulator',
        '2024-06-01'::date,
        '{
            "persoon": {"geboortedatum": "1990-01-01", "geslacht": "v", "opleiding": "hooggeschoold"},
            "functie": {"naam": "T051 Sales Manager", "niveau": 7},
            "contract": {"pc_id": "200", "status": "bediende", "fte_breuk": 1.0},
            "prestatie": {"uren_per_maand": 173.33},
            "loon": {"basisloon": 4000.00}
        }'::jsonb
    )
);


------------------------------------------------------------
-- T2: dim_scenario aangemaakt
------------------------------------------------------------

select is(
    (select count(*)::int from public.dim_scenario
     where scenario_id = (select scenario_id from _t051_scenarios where label = 'main')),
    1,
    'T2 dim_scenario rij aangemaakt'
);


------------------------------------------------------------
-- T3: Synthetic contract met bijbehorende persoon+functie geïnserteerd.
--     Contract heeft geen vorige_contract_id (nieuwe indiensttreding-achtig).
------------------------------------------------------------

select cmp_ok(
    (select count(*)::int from public.dim_contract c
     where c.legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'::uuid
       and c.pc_id = '200'
       and exists (
           select 1 from public.fact_looncomponent fl
           where fl.contract_id = c.contract_id
             and fl.scenario_id = (select scenario_id from _t051_scenarios where label = 'main')
       )),
    '=', 1::int,
    'T3 nieuwe synthetic dim_contract gelinkt aan het scenario'
);


------------------------------------------------------------
-- T4: fact_looncomponent basisloon 4000 EUR aangemaakt voor het scenario.
------------------------------------------------------------

select is(
    (select fl.bedrag from public.fact_looncomponent fl
     join public.dim_looncomponent dl on dl.component_id = fl.component_id
     where fl.scenario_id = (select scenario_id from _t051_scenarios where label = 'main')
       and dl.is_basisloon
       and fl.periode = '2024-06-01'::date
     limit 1),
    4000.0000::numeric(18, 4),
    'T4 fact_looncomponent basisloon = 4000.00 EUR (matches input)'
);


------------------------------------------------------------
-- T5: fact_prestatie uren aangemaakt.
------------------------------------------------------------

select is(
    (select fp.uren from public.fact_prestatie fp
     where fp.contract_id = (
         select c.contract_id from public.dim_contract c
         where c.legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'::uuid
           and exists (
               select 1 from public.fact_looncomponent fl
               where fl.contract_id = c.contract_id
                 and fl.scenario_id = (select scenario_id from _t051_scenarios where label = 'main')
           )
     )
     and fp.periode = '2024-06-01'::date
     limit 1),
    173.3300::numeric(10, 4),
    'T5 fact_prestatie uren = 173.33 (matches input)'
);


------------------------------------------------------------
-- T6: fact_loonkost 7 kostenblokken voor de synthetic contract.
--     create_populatie_loonkost draait voor alle tenant contracten (27 seed +
--     1 synthetic × 7 = 196 total). We assert de 7 kostenblokken van juist
--     de synthetic contract via contract_id.
------------------------------------------------------------

select is(
    (select count(*)::int from public.fact_loonkost fl
     where fl.scenario_id = (select scenario_id from _t051_scenarios where label = 'main')
       and fl.periode = '2024-06-01'::date
       and fl.contract_id = (
           select c.contract_id from public.dim_contract c
           where c.legale_entiteit_id = 'aaaaaaaa-1111-1111-1111-111111111111'::uuid
             and exists (
                 select 1 from public.fact_looncomponent flc
                 where flc.contract_id = c.contract_id
                   and flc.scenario_id = (select scenario_id from _t051_scenarios where label = 'main')
                   and flc.bron_ref like 'simulator_v1_%'
             )
       )),
    7,
    'T6 fact_loonkost 7 kostenblokken voor synthetic contract (via create_populatie_loonkost)'
);


select * from finish();
ROLLBACK;
