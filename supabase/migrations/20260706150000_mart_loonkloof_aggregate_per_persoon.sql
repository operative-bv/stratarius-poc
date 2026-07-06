-- ================================================================
-- ISS-102: refresh_mart_loonkloof — aggregeer op (persoon_id, referentiedatum)
-- ================================================================
--
-- mart_loonkloof PK is (persoon_id, referentiedatum). Bronrouter (lonen_maand
-- CTE) groepeert op méér velden: pc_id, functieniveau, geldig_van,
-- legale_entiteit_id — dus multi-contract personen produceren meerdere rijen.
-- ISS-094 ON CONFLICT DO NOTHING dropte dan silent één rij.
--
-- Fix: extra aggregation-CTE die per (persoon_id, referentiedatum) SUM
-- basis_vte + variabele_vte over alle contracten. Voor niet-key attributen
-- (pc_id, functieniveau, geslacht, geldig_van, legale_entiteit_id):
--   - geslacht is inherent aan persoon → same across contracts, min() ok
--   - functieniveau: kies max (senior contract dominant voor pay-gap analyse)
--   - geldig_van: kies min (oudste start = senioriteit-basis)
--   - pc_id: kies via functieniveau-priority
--   - legale_entiteit_id: kies primaire entiteit met hoogste basis_vte
-- ================================================================


create or replace function public.refresh_mart_loonkloof(
    p_owning_account_id uuid,
    p_rechtsgrondslag   text
)
    returns integer
    language plpgsql
    security definer
    set search_path = public, basejump, pg_temp
as $$
declare
    v_initiator uuid;
    v_rowcount  integer;
begin
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'refresh_mart_loonkloof: authenticated caller required'
            using errcode = '42501';
    end if;

    if p_owning_account_id is null then
        raise exception 'refresh_mart_loonkloof: p_owning_account_id verplicht'
            using errcode = '22023';
    end if;

    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'refresh_mart_loonkloof: p_rechtsgrondslag verplicht (GDPR audit)'
            using errcode = '22023';
    end if;

    if not basejump.has_role_on_account(p_owning_account_id) then
        raise exception 'refresh_mart_loonkloof: geen toegang tot account %', p_owning_account_id
            using errcode = '42501';
    end if;

    perform pg_advisory_xact_lock(
        hashtextextended(p_owning_account_id::text, 43)
    );

    begin
        insert into public.gdpr_access_log (
            user_id, resource_ref, columns_accessed, rechtsgrondslag,
            resulting_rows, event_kind
        )
        values (
            v_initiator, 'refresh_mart_loonkloof',
            array['persoon_id', 'geslacht', 'uurloon_bruto'],
            p_rechtsgrondslag, 0, 'read'
        );
    exception
        when others then
            raise warning 'refresh_mart_loonkloof: audit log insert faalde: [%] %',
                SQLSTATE, SQLERRM;
    end;

    delete from public.mart_loonkloof
    where owning_account_id = p_owning_account_id;

    with kwartaal_eindes as (
        select generate_series('2024-03-31'::date, '2026-12-31'::date, interval '3 months')::date as referentiedatum
    ),
    contract_op_referentie as (
        select
            c.contract_id, c.persoon_id, c.pc_id, c.geldig_van, c.legale_entiteit_id,
            le.owning_account_id,
            f.functieniveau,
            p.geslacht,
            k.referentiedatum
        from public.dim_contract c
        join public.dim_legale_entiteit le on le.legale_entiteit_id = c.legale_entiteit_id
        join public.dim_functie f on f.functie_id = c.functie_id
        join public.dim_persoon p on p.persoon_id = c.persoon_id
        cross join kwartaal_eindes k
        where c.geldig_van <= k.referentiedatum
          and (c.geldig_tot is null or c.geldig_tot > k.referentiedatum)
          and le.owning_account_id = p_owning_account_id
    ),
    -- Per-contract lonen: sum fact_looncomponent bedragen
    lonen_per_contract as (
        select
            cr.contract_id, cr.persoon_id, cr.referentiedatum, cr.pc_id,
            cr.functieniveau, cr.geslacht, cr.geldig_van, cr.legale_entiteit_id,
            cr.owning_account_id,
            coalesce(sum(fl.bedrag) filter (where dl.is_basisloon), 0)::numeric(18, 4) as basis_vte,
            coalesce(sum(fl.bedrag) filter (where dl.rsz_plichtig and not dl.is_basisloon), 0)::numeric(18, 4) as variabele_vte
        from contract_op_referentie cr
        left join public.fact_looncomponent fl
            on fl.contract_id = cr.contract_id
            and fl.periode = date_trunc('month', cr.referentiedatum)::date
            and fl.scenario_id in (
                select s.scenario_id from public.dim_scenario s
                where s.kind = 'baseline'
                  and s.legale_entiteit_id = cr.legale_entiteit_id
            )
        left join public.dim_looncomponent dl on dl.component_id = fl.component_id
        group by cr.contract_id, cr.persoon_id, cr.referentiedatum, cr.pc_id,
                 cr.functieniveau, cr.geslacht, cr.geldig_van, cr.legale_entiteit_id,
                 cr.owning_account_id
    ),
    -- ISS-102: aggregeer per (persoon_id, referentiedatum) — SUM basis+variabele
    -- over alle contracten. Non-key attributen via "primair contract"-heuristiek:
    -- kies de row met hoogste basis_vte (main employment).
    lonen_per_persoon as (
        select distinct on (persoon_id, referentiedatum)
            persoon_id, referentiedatum,
            -- Non-key: kies uit dominant contract
            pc_id, functieniveau, geslacht, geldig_van, legale_entiteit_id, owning_account_id,
            -- Sum totals over alle contracten van deze persoon op deze datum
            sum(basis_vte)     over (partition by persoon_id, referentiedatum) as basis_vte,
            sum(variabele_vte) over (partition by persoon_id, referentiedatum) as variabele_vte
        from lonen_per_contract
        order by persoon_id, referentiedatum, basis_vte desc, contract_id
    )
    insert into public.mart_loonkloof (
        persoon_id, legale_entiteit_id, owning_account_id,
        referentiedatum, kwartaal,
        uurloon_bruto, basis_vte, variabele_vte,
        geslacht, functieniveau, ancienniteit_jaren
    )
    select
        lp.persoon_id,
        lp.legale_entiteit_id,
        lp.owning_account_id,
        lp.referentiedatum,
        extract(year from lp.referentiedatum)::text || '-Q' || extract(quarter from lp.referentiedatum)::text,
        public.uurloon_van_maandloon(lp.basis_vte, lp.pc_id, lp.referentiedatum),
        lp.basis_vte,
        lp.variabele_vte,
        lp.geslacht,
        lp.functieniveau,
        round(((lp.referentiedatum - lp.geldig_van)::numeric / 365.25), 2)::numeric(6, 2)
    from lonen_per_persoon lp
    on conflict (persoon_id, referentiedatum) do nothing;

    get diagnostics v_rowcount = row_count;
    return v_rowcount;
end;
$$;

comment on function public.refresh_mart_loonkloof(uuid, text) is
    'ISS-102: aggregeert bronrouter op (persoon_id, referentiedatum) niveau ipv contract-level. '
    'Multi-contract persoon → SUM basis+variabele, dominant contract (hoogste basisloon) '
    'levert non-key attributen. ON CONFLICT DO NOTHING blijft als defense-in-depth voor race.';
