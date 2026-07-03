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
    select (p_bruto * (pv.enkel_pct + pv.dubbel_pct))::numeric(18, 4)
    from public.param_vakantiegeld pv
    where pv.regime = p_status
      and p_periode >= pv.geldig_van
      and (pv.geldig_tot is null or p_periode < pv.geldig_tot);
$$;

comment on function public.cascade_stap6_vakantiegeld(numeric, text, date) is
    'Cascade stap 6 vakantiegeld provisie = bruto × (enkel_pct + dubbel_pct) via param_vakantiegeld temporele join. Arbeider 2024: 15.38% (vakantiekas dekt enkel+dubbel). Bediende 2024: 7.67% enkel + 92% dubbel via werkgever provisie.';

grant execute on function public.cascade_stap6_vakantiegeld(numeric, text, date) to authenticated;
