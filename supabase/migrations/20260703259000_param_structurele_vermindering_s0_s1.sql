-- ================================================================
-- T-042 HOTFIX: param_structurele_vermindering drempel_s0 + drempel_s1
-- ================================================================
--
-- Fold uit T-026 plan-review round 1: cascade_stap3 formule
--   R = F + α × max(0, S0-S) + δ × max(0, S-S1)
-- vereist S0 en S1 drempels. Schema (T-016) had alleen forfait + coefficient_a
-- + coefficient_b — S0/S1 ontbraken. Deze HOTFIX voegt beide toe.
--
-- Backfill waardes: RSZ 2024 = S0=7207.20, S1=12435.31 (bron socialsecurity.be).
--
-- LOCK TABLE ACCESS EXCLUSIVE (patroon T-041) tegen concurrent insert van
-- rows zonder S0/S1 tussen ADD COLUMN en SET NOT NULL.
--
-- Rollback:
--   alter table public.param_structurele_vermindering
--       drop constraint param_structurele_vermindering_drempel_order,
--       drop column drempel_s0,
--       drop column drempel_s1;

begin;

lock table public.param_structurele_vermindering in access exclusive mode;

alter table public.param_structurele_vermindering
    add column drempel_s0 numeric(18, 4),
    add column drempel_s1 numeric(18, 4);

update public.param_structurele_vermindering
    set drempel_s0 = 7207.20,
        drempel_s1 = 12435.31
    where drempel_s0 is null or drempel_s1 is null;

alter table public.param_structurele_vermindering
    alter column drempel_s0 set not null,
    alter column drempel_s1 set not null;

alter table public.param_structurele_vermindering
    add constraint param_structurele_vermindering_drempel_order
    check (drempel_s0 <= drempel_s1);

commit;

comment on column public.param_structurele_vermindering.drempel_s0 is
    'Drempel laag loon S0 (numeric(18,4) EUR per Constitution money precision). Formule R = (F + alpha × GREATEST(0, S0-S) + delta × GREATEST(0, S-S1)) × mu — merk EXPLICIETE buitenste haakjes: mu schaalt HELE R (fold T-026 operator precedence). RSZ 2024 = 7207.20 (bron socialsecurity.be).';

comment on column public.param_structurele_vermindering.drempel_s1 is
    'Drempel hoog loon S1 (numeric(18,4) EUR). RSZ 2024 = 12435.31. CHECK enforced: drempel_s0 <= drempel_s1.';
