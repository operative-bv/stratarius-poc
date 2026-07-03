-- T-010: dim_sz_behandeling — canonical registry of 5 SZ-behandelingsregimes
-- per PDF Laag 2. Global lookup; geen tenant scoping. dim_looncomponent
-- (T-011) verwijst hierheen voor Principe II data-driven gedrag.
--
-- Principe III: caps voor Gunstregime en VIN-varianten LEVEN in param_plafond
-- (T-015), NIET als attribuut hier. cap_param_plafond_id is een reference-only
-- kolom; ALTER TABLE ... ADD CONSTRAINT komt bij T-015.
--
-- Bron: RSZ instructiegids sectie SZ-behandelingsregimes.
-- https://www.socialsecurity.be/employer/instructions/


create table public.dim_sz_behandeling (
    sz_behandeling_id text primary key,
    regime_naam text not null,
    grondslag_type text not null check (
        grondslag_type in ('werkelijke_waarde', 'forfaitaire_waardering', 'formule', 'nvt', 'gunstig_tot_plafond')
    ),
    werkgevers_sz_pct numeric(6, 4) null,
    cap_param_plafond_id text null,
    bron_url text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.dim_sz_behandeling is
    'Canonical registry of 5 SZ-behandelingsregimes per PDF Laag 2. Global reference. Feeds dim_looncomponent.sz_behandeling_id (T-011) for Principe II data-driven behavior.';
comment on column public.dim_sz_behandeling.grondslag_type is
    'Welke grondslag de werkgevers-SZ berekent op: werkelijke waarde | forfaitaire waardering | formule | n.v.t. | gunstig tot plafond.';
comment on column public.dim_sz_behandeling.werkgevers_sz_pct is
    'Indicatief werkgevers-SZ percentage (numeric(6,4) per Constitution v1.0.1). Canonical values komen uit param_rsz via temporele join in de rekencascade. NULL voor regimes zonder vast tarief (VIN bijzondere formule, Vrijgesteld).';
comment on column public.dim_sz_behandeling.cap_param_plafond_id is
    'Reference (text) naar param_plafond(param_plafond_id). FK-constraint wordt toegevoegd door T-015 (param_plafond migration): ALTER TABLE public.dim_sz_behandeling ADD CONSTRAINT dim_sz_behandeling_cap_fk FOREIGN KEY (cap_param_plafond_id) REFERENCES public.param_plafond(param_plafond_id) ON DELETE RESTRICT. Principe III: caps LEVEN NIET als bedragen op deze tabel.';

alter table public.dim_sz_behandeling enable row level security;

create policy dim_sz_behandeling_read_all on public.dim_sz_behandeling
    for select using (true);

revoke insert, update, delete on public.dim_sz_behandeling from authenticated, public, anon;

create trigger dim_sz_behandeling_set_timestamps
    before insert or update on public.dim_sz_behandeling
    for each row execute function basejump.trigger_set_timestamps();

-- Seed 5 canonical regimes per PDF Laag 2 tabel.
-- cap_param_plafond_id blijft NULL tot T-015 param_plafond aanmaakt en
-- deze rijen backfillt.
--
-- Out-of-scope per PDF footnote: Centenindex ≠ grondslagcap
-- (loonmatigingsbijdrage) leeft in PARAM_INDEX + PARAM_BIJZONDERE_BIJDRAGEN,
-- niet hier.
insert into public.dim_sz_behandeling (sz_behandeling_id, regime_naam, grondslag_type, werkgevers_sz_pct, cap_param_plafond_id, bron_url) values
    ('normaal', 'Normaal loon', 'werkelijke_waarde', 0.2540, null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('vin_forfaitair', 'VIN — forfaitair', 'forfaitaire_waardering', 0.2540, null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('vin_bijzondere_formule', 'VIN — bijzondere formule', 'formule', null, null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('vrijgesteld', 'Vrijgesteld van SZ', 'nvt', null, null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('gunstregime_cap', 'Gunstregime met cap', 'gunstig_tot_plafond', 0.1300, null, 'https://www.socialsecurity.be/employer/instructions/')
on conflict (sz_behandeling_id) do nothing;
