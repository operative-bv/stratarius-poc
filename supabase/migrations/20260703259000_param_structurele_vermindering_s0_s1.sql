-- ================================================================
-- T-042 HOTFIX: param_structurele_vermindering drempel_s0 + drempel_s1
-- ================================================================
--
-- Formule (RSZ instructiegids vanaf 1 april 2024):
--   R_kwartaal = F + α × GREATEST(0, S0 - S) + γ × GREATEST(0, S1 - S)
--
-- Semantiek van kolommen:
--   drempel_s0    = S0  — lage-lonencomponent drempel (kwartaalloon)
--   drempel_s1    = S1  — zeer-lage-lonencomponent drempel (< S0), REPURPOSED
--                         (voorheen "hoge lonen S1" maar die component bestaat
--                          niet meer voor cat 1 vanaf 2024).
--   coefficient_a = α   — hellingscoëfficiënt lage lonen
--   coefficient_b = γ   — hellingscoëfficiënt zeer lage lonen, REPURPOSED
--
-- Cat 1 waardes vanaf 1 april 2024 (bron socialsecurity.be RSZ instructiegids +
--   easypay-group.com cross-check): S0=10.797,67 · S1=6.807,18 · α=0.14 · γ=0.40 · F=0.
-- Cat 2 (social profit) + Cat 3 (beschutte werkplaats): POC_UNVERIFIED; behouden
--   as-is uit T-018 seed. Cross-check per productie-deploy.
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

-- Per-categorie drempels: cat 1 heeft echte 2024 waardes; cat 2 + cat 3 POC_UNVERIFIED.
update public.param_structurele_vermindering
    set drempel_s0 = case werkgeverscategorie
        when 1 then 10797.67   -- Bron: RSZ instructiegids 1 april 2024
        else 7207.20            -- POC_UNVERIFIED cat 2 + cat 3
    end,
        drempel_s1 = case werkgeverscategorie
        when 1 then 6807.18    -- Bron: RSZ instructiegids 1 april 2024 (zeer-lage-lonen)
        else 6807.18            -- POC_UNVERIFIED cat 2 + cat 3
    end
    where drempel_s0 is null or drempel_s1 is null;

alter table public.param_structurele_vermindering
    alter column drempel_s0 set not null,
    alter column drempel_s1 set not null;

-- Constraint: S1 (zeer-lage-lonen drempel) <= S0 (lage-lonen drempel).
alter table public.param_structurele_vermindering
    add constraint param_structurele_vermindering_drempel_order
    check (drempel_s1 <= drempel_s0);

commit;

comment on column public.param_structurele_vermindering.drempel_s0 is
    'Drempel S0 lage-lonencomponent (numeric(18,4) EUR kwartaal). Formule R = (F + alpha × GREATEST(0, S0-S) + gamma × GREATEST(0, S1-S)) × mu / 3 (kwartaal->maand). RSZ 2024 cat 1 = 10797.67 (bron socialsecurity.be, RSZ instructiegids 1 april 2024).';

comment on column public.param_structurele_vermindering.drempel_s1 is
    'Drempel S1 zeer-lage-lonencomponent (numeric(18,4) EUR kwartaal). REPURPOSED — voorheen "hoge lonen" maar die component bestaat niet meer voor cat 1 vanaf 2024. RSZ 2024 cat 1 = 6807.18. CHECK enforced: drempel_s1 <= drempel_s0.';
