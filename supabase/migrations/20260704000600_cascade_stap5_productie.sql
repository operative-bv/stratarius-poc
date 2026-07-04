-- ================================================================
-- T-046: cascade_stap5_bijzondere_bijdragen_productie
-- ================================================================
--
-- Productie-versie van cascade_stap5 met:
--   1. formule_json.toepassing evaluatie: "wg >= N wn" checkt actieve
--      contracten per legale entiteit op p_periode.
--   2. Centenindex-bijdrage: als loonmatiging toegepast wordt, extra
--      0.5 × max(0, bruto - drempel_bruto), waar drempel_bruto uit
--      param_index voor contract's PC/periode komt.
--
-- Design: NIEUWE functie naast T-043 stap5 (die blijft bestaan voor
-- simulator page.tsx en backward compat). Nieuwe signature accepteert
-- contract_id om entiteit + PC te resolven.
--
-- Cascade populatie_snapshot wordt in aparte migration geswitched naar
-- deze productie-functie zodat /populatie de correcte productie-cijfers
-- toont. Simulator page.tsx blijft op T-043 stap5 (single-contract flow
-- zonder tenant-context, POC UX ongeraakt).
--
-- Constitution Principe I: temporele join op alle 3 param tabellen.
-- Constitution Principe II: alle tarieven + drempels + toepassing regels
--   data-driven; geen hardcoded 20 of 10 in function-body (uit
--   formule_json->>'toepassing' pattern).
-- Constitution Principe III: pure SQL functie STABLE PARALLEL SAFE.
-- Constitution Principe V: test-first commit 57-.
--
-- Rollback:
--   DROP FUNCTION public.cascade_stap5_bijzondere_bijdragen_productie(uuid, numeric, date);


create or replace function public.cascade_stap5_bijzondere_bijdragen_productie(
    p_contract_id uuid,
    p_bruto       numeric(18, 4),
    p_periode     date
)
    returns numeric(18, 4)
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    with contract_ctx as (
        select c.contract_id, c.pc_id, c.legale_entiteit_id
        from public.dim_contract c
        where c.contract_id = p_contract_id
    ),
    wg_count as (
        select count(distinct c.persoon_id)::int as employee_count
        from public.dim_contract c
        where c.legale_entiteit_id = (select legale_entiteit_id from contract_ctx)
          and c.geldig_van <= p_periode
          and (c.geldig_tot is null or c.geldig_tot > p_periode)
    ),
    drempel as (
        select pi.drempel_bruto
        from public.param_index pi
        where pi.pc_id = (select pc_id from contract_ctx)
          and p_periode >= pi.geldig_van
          and (pi.geldig_tot is null or p_periode < pi.geldig_tot)
        limit 1
    ),
    bijdragen as (
        select pb.type, pb.tarief, pb.formule_json
        from public.param_bijzondere_bijdragen pb
        where p_periode >= pb.geldig_van
          and (pb.geldig_tot is null or p_periode < pb.geldig_tot)
    ),
    toegepast as (
        -- Filter op formule_json.toepassing "wg >= N wn" wanneer aanwezig.
        -- Rows zonder toepassing worden altijd toegepast.
        select b.type, b.tarief
        from bijdragen b, wg_count w
        where
            not (b.formule_json ? 'toepassing')
            or b.formule_json ->> 'toepassing' !~ '^wg >= \d+ wn$'
            or w.employee_count >= substring(b.formule_json ->> 'toepassing' from '(\d+)')::int
    ),
    centenindex as (
        -- Extra loonmatiging component: 0.5 × indexbesparing boven drempel_bruto.
        -- Alleen actief wanneer loonmatiging überhaupt toegepast wordt.
        select
            case
                when exists (select 1 from toegepast where type = 'loonmatiging')
                then (0.5 * greatest(0::numeric(18,4), p_bruto - coalesce((select drempel_bruto from drempel), 0)))::numeric(18, 4)
                else 0::numeric(18, 4)
            end as bijdrage
        from contract_ctx  -- forces cte to yield 0 rows when contract niet bestaat
    )
    select (
        coalesce((select sum(tarief * p_bruto) from toegepast), 0)
        + coalesce((select bijdrage from centenindex), 0)
    )::numeric(18, 4)
    from contract_ctx;  -- yields 0 rows als contract niet bestaat -> function returns NULL
$$;

comment on function public.cascade_stap5_bijzondere_bijdragen_productie(uuid, numeric, date) is
    'Cascade stap 5 productie: bijzondere bijdragen met toepassing filter (wg >= N wn) via employee-count per legale entiteit, en centenindex (0.5 × indexbesparing boven param_index.drempel_bruto) additief bij loonmatiging. Principe II data-driven. NULL contract: onbekende contract_id -> NULL (contract_ctx CTE geen rijen).';

grant execute on function public.cascade_stap5_bijzondere_bijdragen_productie(uuid, numeric, date) to authenticated;
