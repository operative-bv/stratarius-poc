-- ================================================================
-- T-045: cascade_stap4_doelgroepverminderingen met non-cumulatie policy
-- ================================================================
--
-- Belgische wet: verschillende doelgroepverminderingen mogen meestal niet
-- gecombineerd worden voor dezelfde werknemer binnen een gewest. Federale
-- verminderingen (bv. mentor) cumuleren wél soms met gewest-specifieke.
--
-- Design: voorwaarden_json extension met optionele "cumulatie_groep" key.
--   - Rows in dezelfde cumulatie_groep zijn wederzijds exclusief.
--   - Per groep wint de row met de hoogste berekende bijdrage
--     (forfait * coefficient * mu) — beneficial-to-employer default,
--     zoals in Belgische praktijk.
--   - Rows zonder cumulatie_groep krijgen een unieke bucket via
--     param_doelgroep_id::text → altijd meegeteld (backward compat).
--
-- Waarom optie B (json-extension) en niet optie A (dim_doelgroep_cumulatie
-- exclusion tabel):
--   - Symmetrisch, geen A->B/B->A duplicaat rijen.
--   - Schaalt O(n) ipv O(n²) pairs.
--   - Data leeft bij de doelgroep (Principe II locality).
--   - Bestaand voorwaarden_json patroon; import-scripts blijven werken.
--
-- Backward compat: bestaande rijen zonder cumulatie_groep key gedragen zich
-- identiek aan huidige som-behavior (elke row eigen bucket via
-- param_doelgroep_id::text).
--
-- Signature ongewijzigd — CREATE OR REPLACE volstaat.
--
-- Rollback: revert naar T-027 versie (som ipv per-bucket max).


create or replace function public.cascade_stap4_doelgroepverminderingen(
    p_contract_id   uuid,
    p_rsz_grondslag numeric(18, 4),
    p_mu            numeric(6, 4),
    p_periode       date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
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
        select
            pdv.param_doelgroep_id,
            pdv.forfait,
            pdv.coefficient,
            pdv.voorwaarden_json,
            cc.dienstverband_van,
            cc.persoon_id,
            cc.geboortedatum,
            cc.opleidingsniveau
        from public.param_doelgroepvermindering pdv
        cross join contract_context cc
        where pdv.gewest = cc.gewest
          and p_periode >= pdv.geldig_van
          and (pdv.geldig_tot is null or p_periode < pdv.geldig_tot)
    ),
    matchend as (
        select
            k.param_doelgroep_id,
            k.voorwaarden_json ->> 'cumulatie_groep' as cumulatie_groep,
            (k.forfait * k.coefficient * p_mu) as bijdrage
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
    ),
    per_bucket as (
        -- Non-cumulatie: rows in dezelfde cumulatie_groep concurreren; hoogste bijdrage wint.
        -- Rows zonder cumulatie_groep krijgen een unieke bucket via param_doelgroep_id::text
        -- (dus altijd meegeteld — backward compat met huidige som-behavior).
        select coalesce(cumulatie_groep, param_doelgroep_id::text) as bucket,
               max(bijdrage) as max_bijdrage
        from matchend
        group by 1
    )
    select coalesce(sum(max_bijdrage), 0)::numeric(18, 4)
    from per_bucket;
$$;

comment on function public.cascade_stap4_doelgroepverminderingen(uuid, numeric, numeric, date) is
    'Cascade stap 4 met non-cumulatie: matchende doelgroepverminderingen groeperen per voorwaarden_json.cumulatie_groep; per groep wint hoogste bijdrage (forfait*coefficient*mu). Rows zonder cumulatie_groep krijgen unieke bucket (via param_doelgroep_id) => altijd meegeteld (backward compat). Principe II JSONB rule engine + non-cumulatie policy. Principe IV: mu drijft pro rata.';
