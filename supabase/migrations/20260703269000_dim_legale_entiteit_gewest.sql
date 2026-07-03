-- T-027 HOTFIX A: dim_legale_entiteit.gewest voor doelgroepverminderingen matching
begin;
lock table public.dim_legale_entiteit in access exclusive mode;

alter table public.dim_legale_entiteit
    add column gewest text check (gewest is null or gewest in ('vlaanderen', 'wallonie', 'brussel'));

commit;

comment on column public.dim_legale_entiteit.gewest is
    'Belgische gewest (vlaanderen=VDAB / wallonie=Forem / brussel=Actiris). Nullable met CHECK — cascade stap 4 filtert null out. Post-6e-Staatshervorming key voor doelgroepverminderingen matching.';
