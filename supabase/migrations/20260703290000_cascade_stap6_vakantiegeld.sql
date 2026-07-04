-- T-044: cascade_stap6_vakantiegeld provisie
-- Eindejaarspremie deferred als ISS (vereist aparte param-tabel + gelijkstellingen).

create or replace function public.cascade_stap6_vakantiegeld(
    p_bruto  numeric(18, 4),
    p_status text,
    p_periode date
)
    returns numeric(18, 4)
    language sql stable parallel safe
    set search_path = public, pg_temp
as $$
    -- param_vakantiegeld bevat JAARLIJKSE rates (enkel + dubbel als deel van jaarloon).
    -- Cascade output is maandelijkse provisie → deel door 12.
    select (p_bruto * (pv.enkel_pct + pv.dubbel_pct) / 12)::numeric(18, 4)
    from public.param_vakantiegeld pv
    where pv.regime = p_status
      and p_periode >= pv.geldig_van
      and (pv.geldig_tot is null or p_periode < pv.geldig_tot);
$$;

comment on function public.cascade_stap6_vakantiegeld(numeric, text, date) is
    'Cascade stap 6 vakantiegeld maandelijkse provisie = bruto × (enkel_pct + dubbel_pct) / 12. Param bevat jaarlijkse rates: arbeider 15.38% via vakantiekas, bediende 7.67% enkel + 92% dubbel via werkgever provisie. Cascade divide-door-12 voor maand-accrual.';

grant execute on function public.cascade_stap6_vakantiegeld(numeric, text, date) to authenticated;
