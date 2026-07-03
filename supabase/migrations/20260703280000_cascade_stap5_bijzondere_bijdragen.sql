-- T-043: cascade_stap5_bijzondere_bijdragen
--
-- Som van FSO + BEV + asbest + loonmatiging tarieven × grondslag.
-- POC simplificaties (ISS follow-ups):
--   - formule_json.toepassing conditions ("wg >= 20 wn") niet geëvalueerd
--   - centenindex-bijdrage (50% × indexbesparing) niet apart berekend;
--     loonmatiging = flat 7.75% per T-020 seed
--
-- Rollback: DROP FUNCTION public.cascade_stap5_bijzondere_bijdragen(numeric, date);

create or replace function public.cascade_stap5_bijzondere_bijdragen(
    p_grondslag numeric(18, 4),
    p_periode   date
)
    returns numeric(18, 4)
    language sql stable parallel safe
    set search_path = public, pg_temp
as $$
    select coalesce(sum(pb.tarief * p_grondslag), 0)::numeric(18, 4)
    from public.param_bijzondere_bijdragen pb
    where p_periode >= pb.geldig_van
      and (pb.geldig_tot is null or p_periode < pb.geldig_tot);
$$;

comment on function public.cascade_stap5_bijzondere_bijdragen(numeric, date) is
    'Cascade stap 5: som van bijzondere bijdragen tarieven × grondslag. Data-driven via param_bijzondere_bijdragen (Principe II). POC skipt toepassing conditions en centenindex-berekening (filed als ISS).';

grant execute on function public.cascade_stap5_bijzondere_bijdragen(numeric, date) to authenticated;
