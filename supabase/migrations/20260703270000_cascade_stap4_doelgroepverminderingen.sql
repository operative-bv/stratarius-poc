-- T-027: cascade_stap4_doelgroepverminderingen JSONB rule engine
--
-- Principe II data-driven: voorwaarden_json evaluatie zonder hardcoded age brackets.
-- Principe IV: μ (niet fte_breuk) drijft pro rata.
-- Cumulatie POC: som van alle matchende doelgroepen × μ. Belgische wet kan
--   non-cumulatie eisen — filed als follow-up ISS.
-- Rollback: DROP FUNCTION public.cascade_stap4_doelgroepverminderingen(uuid, numeric, numeric, date);

create or replace function public.cascade_stap4_doelgroepverminderingen(
    p_contract_id   uuid,
    p_rsz_grondslag numeric(18, 4),
    p_mu            numeric(6, 4),
    p_periode       date
)
    returns numeric(18, 4)
    language sql stable parallel safe
    set search_path = public, pg_temp
as $$
    with
    contract_context as (
        select
            c.contract_id,
            c.persoon_id,
            c.geldig_van as dienstverband_van,
            le.gewest,
            p.geboortedatum,
            p.opleidingsniveau
        from public.dim_contract c
        join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id
        join public.dim_persoon p on p.persoon_id = c.persoon_id
        where c.contract_id = p_contract_id
          and le.gewest is not null
    ),
    kandidaten as (
        select pdv.forfait, pdv.coefficient, pdv.voorwaarden_json,
               cc.dienstverband_van, cc.persoon_id,
               cc.geboortedatum, cc.opleidingsniveau
        from public.param_doelgroepvermindering pdv
        cross join contract_context cc
        where pdv.gewest = cc.gewest
          and p_periode >= pdv.geldig_van
          and (pdv.geldig_tot is null or p_periode < pdv.geldig_tot)
    ),
    matchend as (
        select k.forfait, k.coefficient
        from kandidaten k
        where
            -- min_leeftijd
            (not (k.voorwaarden_json ? 'min_leeftijd')
             or extract(year from age(p_periode, k.geboortedatum)) >= (k.voorwaarden_json->>'min_leeftijd')::int)
            -- max_leeftijd
            and (not (k.voorwaarden_json ? 'max_leeftijd')
                 or extract(year from age(p_periode, k.geboortedatum)) <= (k.voorwaarden_json->>'max_leeftijd')::int)
            -- max_refertekwartaalloon_eur (rsz_grondslag * 3 = kwartaalloon proxy)
            and (not (k.voorwaarden_json ? 'max_refertekwartaalloon_eur')
                 or p_rsz_grondslag * 3 <= (k.voorwaarden_json->>'max_refertekwartaalloon_eur')::numeric(18, 4))
            -- kwalificatie
            and (not (k.voorwaarden_json ? 'kwalificatie')
                 or k.voorwaarden_json->>'kwalificatie' = k.opleidingsniveau)
            -- duur_maanden (max dienstverband duur)
            and (not (k.voorwaarden_json ? 'duur_maanden')
                 or (extract(year from age(p_periode, k.dienstverband_van))::int * 12
                     + extract(month from age(p_periode, k.dienstverband_van))::int) <= (k.voorwaarden_json->>'duur_maanden')::int)
            -- werkloos_min_maanden
            and (not (k.voorwaarden_json ? 'werkloos_min_maanden')
                 or coalesce((
                     select sum(extract(year from age(av.werkloosheidsperiode_tot, av.werkloosheidsperiode_van))::int * 12
                              + extract(month from age(av.werkloosheidsperiode_tot, av.werkloosheidsperiode_van))::int)
                     from public.dim_persoon_arbeidsverleden av
                     where av.persoon_id = k.persoon_id
                       and av.werkloosheidsperiode_tot is not null
                       and av.werkloosheidsperiode_tot <= k.dienstverband_van
                 ), 0) >= (k.voorwaarden_json->>'werkloos_min_maanden')::int)
    )
    select coalesce(sum(m.forfait * m.coefficient * p_mu), 0)::numeric(18, 4)
    from matchend m;
$$;

comment on function public.cascade_stap4_doelgroepverminderingen(uuid, numeric, numeric, date) is
    'Cascade stap 4: som van matchende doelgroepverminderingen (gewest × doelgroep × periode). Principe II JSONB rule engine voor voorwaarden_json (min/max_leeftijd, kwalificatie, max_refertekwartaalloon_eur, duur_maanden, werkloos_min_maanden). Principe IV: mu drijft pro rata. POC cumulatie: som alle matches; productie non-cumulatie regels via ISS-nieuw.';

grant execute on function public.cascade_stap4_doelgroepverminderingen(uuid, numeric, numeric, date) to authenticated;
