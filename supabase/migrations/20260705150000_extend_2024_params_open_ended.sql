-- ================================================================
-- Fase 2 (fiscale audit): 2024 param rijen open-ended maken
-- ================================================================
--
-- Alle 11 param_* tabellen zijn geseed voor 2024-01-01 t/m 2025-01-01.
-- Voor periodes > 2024-12-31 retourneert de cascade NULL want er is
-- geen matching row. Vandaag is 2026-07-05.
--
-- Safety net: zet geldig_tot = NULL op alle 2024-rijen zodat ze
-- geldig blijven totdat we in fase 3 expliciete 2025 + 2026 rijen
-- toevoegen. Bij die inserts wordt geldig_tot van 2024-rij expliciet
-- geset naar de nieuwe geldig_van, waardoor het effective-dating
-- interval sluit.
--
-- Idempotent: UPDATE naar NULL is een no-op als een 2025-rij al is
-- toegevoegd (die zou de 2024-rij al terug geldig_tot='2025-01-01'
-- gezet hebben).
-- ================================================================

-- Wanneer een 2025 of later rij al bestaat, laten we de bestaande
-- geldig_tot ongewijzigd (die is dan al correct afgesloten).

update public.param_rsz
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_rsz t
          where t.status = param_rsz.status
            and t.werkgeverscategorie = param_rsz.werkgeverscategorie
            and t.geldig_van > param_rsz.geldig_van
      );

update public.param_structurele_vermindering
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_structurele_vermindering t
          where t.werkgeverscategorie = param_structurele_vermindering.werkgeverscategorie
            and t.geldig_van > param_structurele_vermindering.geldig_van
      );

update public.param_doelgroepvermindering
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_doelgroepvermindering t
          where t.gewest = param_doelgroepvermindering.gewest
            and t.doelgroep = param_doelgroepvermindering.doelgroep
            and t.geldig_van > param_doelgroepvermindering.geldig_van
      );

update public.param_arbeidsduur
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_arbeidsduur t
          where t.pc_id = param_arbeidsduur.pc_id
            and t.geldig_van > param_arbeidsduur.geldig_van
      );

update public.param_vakantiegeld
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_vakantiegeld t
          where t.regime = param_vakantiegeld.regime
            and t.geldig_van > param_vakantiegeld.geldig_van
      );

update public.param_index
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_index t
          where t.pc_id = param_index.pc_id
            and t.geldig_van > param_index.geldig_van
      );

update public.param_wagen_mobiliteit
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_wagen_mobiliteit t
          where t.geldig_van > param_wagen_mobiliteit.geldig_van
      );

update public.param_bijzondere_bijdragen
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_bijzondere_bijdragen t
          where t.type = param_bijzondere_bijdragen.type
            and t.geldig_van > param_bijzondere_bijdragen.geldig_van
      );

update public.param_extralegaal
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_extralegaal t
          where t.voordeeltype = param_extralegaal.voordeeltype
            and t.geldig_van > param_extralegaal.geldig_van
      );

update public.param_sectorbijdrage
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_sectorbijdrage t
          where t.pc_id = param_sectorbijdrage.pc_id
            and t.fonds = param_sectorbijdrage.fonds
            and t.geldig_van > param_sectorbijdrage.geldig_van
      );

update public.param_arbeidsongevallen
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_arbeidsongevallen t
          where t.pc_id = param_arbeidsongevallen.pc_id
            and t.geldig_van > param_arbeidsongevallen.geldig_van
      );

update public.param_eindejaarspremie
    set geldig_tot = null
    where geldig_van = '2024-01-01' and geldig_tot = '2025-01-01'
      and not exists (
          select 1 from public.param_eindejaarspremie t
          where t.pc_id = param_eindejaarspremie.pc_id
            and t.geldig_van > param_eindejaarspremie.geldig_van
      );

-- Diagnostiek: hoeveel rijen zijn nu open-ended?
do $$
declare
    v_total int;
begin
    select
        (select count(*) from public.param_rsz where geldig_tot is null) +
        (select count(*) from public.param_structurele_vermindering where geldig_tot is null) +
        (select count(*) from public.param_doelgroepvermindering where geldig_tot is null) +
        (select count(*) from public.param_arbeidsduur where geldig_tot is null) +
        (select count(*) from public.param_vakantiegeld where geldig_tot is null) +
        (select count(*) from public.param_index where geldig_tot is null) +
        (select count(*) from public.param_wagen_mobiliteit where geldig_tot is null) +
        (select count(*) from public.param_bijzondere_bijdragen where geldig_tot is null) +
        (select count(*) from public.param_extralegaal where geldig_tot is null) +
        (select count(*) from public.param_sectorbijdrage where geldig_tot is null) +
        (select count(*) from public.param_arbeidsongevallen where geldig_tot is null) +
        (select count(*) from public.param_eindejaarspremie where geldig_tot is null)
    into v_total;
    raise notice 'Fase 2 complete: % param rijen zijn nu open-ended (geldig_tot=null)', v_total;
end $$;
