-- ================================================================
-- T-054: dim_scenario param_snapshot_batch_id + get_current_snapshot_batch_id
-- ================================================================
--
-- Scenario reproducibility ref: aan dim_scenario wordt een NULL-able uuid
-- kolom toegevoegd die verwijst naar audit_parameter_snapshot.snapshot_batch_id.
-- Doel: op scenario-creatie de "actieve" parametersnapshot vastleggen, zodat
-- er later verifieerbaar is welke parameterset actief was ten tijde van
-- scenario-uitwerking.
--
-- Semantic-only reference (geen FK-enforcement):
--   audit_parameter_snapshot heeft unique (snapshot_batch_id, tabel_naam) —
--   13 rijen per batch, niet 1. FK zou single-row target vereisen; batch_id
--   verwijst naar de logische groep.
--   Precedent: fact_loonkost.snapshot_batch_id (T-022) is ook semantic-only ref.
--
-- POC-scope limitation: geen historische reconstructie mogelijkheid.
-- audit_parameter_snapshot bewaart checksums + metadata, niet de daadwerkelijke
-- parameter rijen. Als een parameter row later gecorrigeerd wordt, geeft
-- effective-dating de nieuwe waarde terug — snapshot_batch_id is dan een
-- "waarschuwings-ref" (checksum-mismatch mogelijk).
-- Full reproducibility vereist snapshot preservation (aparte follow-up).
--
-- Ook: helper functie get_current_snapshot_batch_id() returnt de meest recente
-- batch. Scenario-RPCs (create_what_if_scenario, create_wagen_scenario) kunnen
-- deze aanroepen om auto-populate te doen. Voor POC blijft die auto-populate
-- optioneel — losse RPC-update is aparte migration.
--
-- Rollback:
--   ALTER TABLE public.dim_scenario DROP COLUMN param_snapshot_batch_id;
--   DROP FUNCTION public.get_current_snapshot_batch_id();


-- ================================================================
-- 1) ALTER TABLE dim_scenario
-- ================================================================

alter table public.dim_scenario
    add column param_snapshot_batch_id uuid null;

comment on column public.dim_scenario.param_snapshot_batch_id is
    'Semantic reference naar audit_parameter_snapshot.snapshot_batch_id — parametersnapshot actief bij scenario-creatie. NULL = geen ref (impliciet current). POC: reference-only, geen enforcement of historische reconstructie (vereist snapshot preservation, out-of-scope).';


-- ================================================================
-- 2) HELPER FUNCTION get_current_snapshot_batch_id
-- ================================================================

create or replace function public.get_current_snapshot_batch_id()
    returns uuid
    language sql
    stable
    parallel safe
    set search_path = public, pg_temp
as $$
    select snapshot_batch_id
    from public.audit_parameter_snapshot
    order by taken_at desc
    limit 1;
$$;

comment on function public.get_current_snapshot_batch_id() is
    'Returns most recent parameter snapshot batch id (via audit_parameter_snapshot ordered by taken_at). Gebruikt door scenario-RPCs voor auto-populate van dim_scenario.param_snapshot_batch_id. NULL wanneer audit_parameter_snapshot leeg is.';

grant execute on function public.get_current_snapshot_batch_id() to authenticated;
