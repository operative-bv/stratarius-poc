-- ================================================================
-- ISS-095: freshness contract voor parameter changes
-- ================================================================
--
-- Convergent finding: Claude Agent 1 #4 (85/100) + Codex I3 (95/100).
-- refreshed_at kolom bestaat op mart_populatie_loonkost + mart_loonkloof
-- maar wordt alleen als UI-metadata gebruikt. Cache-invalidatie hangt
-- puur aan mutation-RPCs. Als een param_rsz / param_bedrijfswagen_forfait
-- migration een tenant's berekening verandert, wordt de cache NOOIT
-- ongeldig.
--
-- Onze trigger-based invalidatie uit ISS-089 werkt alleen voor TENANT-
-- scoped tabellen (fact_*, dim_*). param_* tabellen zijn GLOBAAL —
-- gedeeld tussen alle tenants — dus tenant-gescopeerde invalidation
-- helpt niet.
--
-- Fix: STATEMENT-level trigger op elke param_* tabel die BEIDE mart-
-- caches TRUNCATE't. Één parameter-wijziging = wereldwijde cache-refresh
-- op eerstvolgende page-visit per tenant.
--
-- Trade-off: bij een param_* migratie krijgt elke tenant een cache-miss
-- op de eerstvolgende bezoek → extra latency. Acceptable — parameter-
-- migraties zijn zeldzaam (jaarlijkse RSZ-update, wetswijziging). De
-- alternatieve consequentie (stale cache voor alle tenants indefinitely)
-- is veel erger.
--
-- Alternatieven overwogen:
-- - TTL op refreshed_at: arbitrair (24h?), mist mid-day updates
-- - param_snapshot_batch_id op mart rows: schema change, extra join per
--   page-load, complexer
-- - Documented convention "elke param_* migratie MUST TRUNCATE marts":
--   te makkelijk te vergeten. Trigger is enforced.
-- ================================================================


-- ================================================================
-- Trigger function: TRUNCATE alle mart-caches (globaal)
-- ================================================================

create or replace function public.invalidate_all_marts_on_param_change()
    returns trigger
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
begin
    -- TRUNCATE ipv DELETE: sneller voor volledige mart wipe.
    -- Beide caches worden opnieuw opgebouwd op eerstvolgende page-visit
    -- per tenant via auto-populate.
    truncate public.mart_populatie_loonkost;
    truncate public.mart_loonkloof;
    return null;
end;
$$;

comment on function public.invalidate_all_marts_on_param_change() is
    'ISS-095: STATEMENT-level trigger function. Wist BEIDE mart-caches '
    'globaal wanneer een param_* tabel wijzigt. Cascade-berekening baseert '
    'zich op param_* waarden — elke wijziging maakt alle bestaande cache-'
    'rows semantisch stale.';


-- ================================================================
-- Triggers op alle param_* tabellen
-- ================================================================

-- param_rsz
drop trigger if exists trg_invalidate_marts_param_rsz on public.param_rsz;
create trigger trg_invalidate_marts_param_rsz
    after insert or update or delete on public.param_rsz
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_structurele_vermindering
drop trigger if exists trg_invalidate_marts_param_structurele on public.param_structurele_vermindering;
create trigger trg_invalidate_marts_param_structurele
    after insert or update or delete on public.param_structurele_vermindering
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_doelgroepvermindering
drop trigger if exists trg_invalidate_marts_param_doelgroep on public.param_doelgroepvermindering;
create trigger trg_invalidate_marts_param_doelgroep
    after insert or update or delete on public.param_doelgroepvermindering
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_vakantiegeld
drop trigger if exists trg_invalidate_marts_param_vakantiegeld on public.param_vakantiegeld;
create trigger trg_invalidate_marts_param_vakantiegeld
    after insert or update or delete on public.param_vakantiegeld
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_eindejaarspremie
drop trigger if exists trg_invalidate_marts_param_eindejaarspremie on public.param_eindejaarspremie;
create trigger trg_invalidate_marts_param_eindejaarspremie
    after insert or update or delete on public.param_eindejaarspremie
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_bijzondere_bijdragen
drop trigger if exists trg_invalidate_marts_param_bijzondere on public.param_bijzondere_bijdragen;
create trigger trg_invalidate_marts_param_bijzondere
    after insert or update or delete on public.param_bijzondere_bijdragen
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_wagen_mobiliteit
drop trigger if exists trg_invalidate_marts_param_wagen on public.param_wagen_mobiliteit;
create trigger trg_invalidate_marts_param_wagen
    after insert or update or delete on public.param_wagen_mobiliteit
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_arbeidsongevallen
drop trigger if exists trg_invalidate_marts_param_arbeidsongevallen on public.param_arbeidsongevallen;
create trigger trg_invalidate_marts_param_arbeidsongevallen
    after insert or update or delete on public.param_arbeidsongevallen
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_extralegaal
drop trigger if exists trg_invalidate_marts_param_extralegaal on public.param_extralegaal;
create trigger trg_invalidate_marts_param_extralegaal
    after insert or update or delete on public.param_extralegaal
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_index
drop trigger if exists trg_invalidate_marts_param_index on public.param_index;
create trigger trg_invalidate_marts_param_index
    after insert or update or delete on public.param_index
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_plafond
drop trigger if exists trg_invalidate_marts_param_plafond on public.param_plafond;
create trigger trg_invalidate_marts_param_plafond
    after insert or update or delete on public.param_plafond
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_arbeidsduur
drop trigger if exists trg_invalidate_marts_param_arbeidsduur on public.param_arbeidsduur;
create trigger trg_invalidate_marts_param_arbeidsduur
    after insert or update or delete on public.param_arbeidsduur
    for each statement
    execute function public.invalidate_all_marts_on_param_change();

-- param_sectorbijdrage
drop trigger if exists trg_invalidate_marts_param_sectorbijdrage on public.param_sectorbijdrage;
create trigger trg_invalidate_marts_param_sectorbijdrage
    after insert or update or delete on public.param_sectorbijdrage
    for each statement
    execute function public.invalidate_all_marts_on_param_change();
