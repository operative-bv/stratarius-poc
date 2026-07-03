-- T-013: dim_prestatiecode — prestatiecodes met gedragstags voor tijd-uren.
--
-- Verschilt van dim_looncomponent (T-011) doordat prestatiecodes over TIJD
-- gaan (uren/dagen), niet bedragen. Gedragstags bepalen HOE tijd meetelt voor
-- mu (Principe IV), vakantiegeld-provisie, en RSZ-grondslag.
--
-- Principe IV embodied: tijdelijke_urenvermindering heeft telt_voor_mu=false
-- terwijl dim_contract.fte_breuk=1 blijft → μ zakt onder 1, exact het scenario
-- waar Constitution's "twee breuken, geen één" over gaat.
--
-- Principe II embodied: overuren_50 en overuren_100 onderscheiden zich via
-- de toeslag_pct kolom (behavioral tag), NOOIT via prestatiecode identity.
-- Cascade leest toeslag_pct voor overloon-berekening.


create table public.dim_prestatiecode (
    prestatiecode text primary key,
    naam text not null,
    familie text not null,

    -- Principe II gedragstags — NOT NULL zonder default forceert expliciet setten.
    telt_voor_mu boolean not null,
    gelijkgesteld_rsz boolean not null,
    gelijkgesteld_vakantiegeld boolean not null,

    betaalbron text not null check (betaalbron in ('werkgever', 'mutualiteit', 'riziv', 'rva', 'vakantiekas')),
    toeslag_pct numeric(4, 2) null check (toeslag_pct is null or (toeslag_pct >= 0 and toeslag_pct <= 2)),

    bron_url text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.dim_prestatiecode is
    'Prestatiecode-catalogus met gedragstags voor tijd (uren/dagen). Global reference. Rekencascade leest gedragstags via fact_prestatie.prestatiecode FK; NOOIT switching op prestatiecode identity. Bron: PDF Laag 2 + RIZIV/RVA/RSZ documentatie.';

comment on column public.dim_prestatiecode.telt_voor_mu is
    'Principe II + IV gedragstag: telt uren mee voor mu = Q/S (effectieve prestatiebreuk)? KRITISCH voor tijdelijke_urenvermindering: false → mu < 1 terwijl contract fte_breuk = 1 blijft. Dit is Constitution "twee breuken, geen één" in praktijk.';
comment on column public.dim_prestatiecode.gelijkgesteld_rsz is
    'Principe II gedragstag: telt tijd als gelijkgestelde periode voor RSZ? Bv arbeidsongeschikt gewaarborgd loon, ADV-dag, feestdag = true.';
comment on column public.dim_prestatiecode.gelijkgesteld_vakantiegeld is
    'Principe II gedragstag: telt tijd mee voor vakantiegeld-opbouw? KRITISCH arb/bed onderscheid: bediende wettelijke vakantie = true (opbouw volgende jaar), arbeider wettelijke vakantie = false (opbouw zit al in vakantiekas).';
comment on column public.dim_prestatiecode.betaalbron is
    'Wie betaalt de gewerkte/afwezigheids-uren: werkgever | mutualiteit | riziv | rva | vakantiekas. Cascade gebruikt dit voor kost-attributie en RSZ-behandeling. Arbeidsongeschikt = 2 fasen: gewaarborgd_loon (werkgever) → mutualiteit.';
comment on column public.dim_prestatiecode.toeslag_pct is
    'Principe II behavioral tag voor overuren-toeslag. 0.50 voor overuren 50%, 1.00 voor overuren 100%, NULL voor niet-overuren. Cascade leest deze kolom voor overloon-berekening (uren * uurloon * (1 + toeslag_pct)); NOOIT switching op prestatiecode identity.';

alter table public.dim_prestatiecode enable row level security;

create policy dim_prestatiecode_read_all on public.dim_prestatiecode
    for select using (true);

revoke insert, update, delete on public.dim_prestatiecode from authenticated, public, anon;

create index dim_prestatiecode_familie_idx on public.dim_prestatiecode (familie);

create trigger dim_prestatiecode_set_timestamps
    before insert or update on public.dim_prestatiecode
    for each row execute function basejump.trigger_set_timestamps();


-- Seed 12 canonieke prestatiecodes per PDF Laag 2 families-tabel.
insert into public.dim_prestatiecode (prestatiecode, naam, familie, telt_voor_mu, gelijkgesteld_rsz, gelijkgesteld_vakantiegeld, betaalbron, toeslag_pct, bron_url) values
    ('normaal_gewerkt', 'Normaal gewerkt', 'gewerkt', true, false, true, 'werkgever', null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('overuren_50', 'Overuren 50%', 'overuren', true, false, true, 'werkgever', 0.50, 'https://www.socialsecurity.be/employer/instructions/'),
    ('overuren_100', 'Overuren 100%', 'overuren', true, false, true, 'werkgever', 1.00, 'https://www.socialsecurity.be/employer/instructions/'),
    ('adv_dag', 'ADV-dag', 'adv', true, true, true, 'werkgever', null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('feestdag', 'Feestdag', 'feestdagen', true, true, true, 'werkgever', null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('vakantie_wettelijk_arb', 'Wettelijke vakantie (arbeider)', 'vakantie', true, true, false, 'vakantiekas', null, 'https://www.rjv.fgov.be/'),
    ('vakantie_wettelijk_bed', 'Wettelijke vakantie (bediende)', 'vakantie', true, true, true, 'werkgever', null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('vakantie_extralegaal', 'Extralegale vakantie', 'vakantie', true, true, true, 'werkgever', null, 'https://www.socialsecurity.be/employer/instructions/'),
    ('arbeidsongeschikt_gewaarborgd', 'Arbeidsongeschikt (gewaarborgd loon)', 'arbeidsongeschiktheid', false, true, true, 'werkgever', null, 'https://www.riziv.fgov.be/'),
    ('arbeidsongeschikt_mutualiteit', 'Arbeidsongeschikt (mutualiteit/RIZIV)', 'arbeidsongeschiktheid', false, true, true, 'mutualiteit', null, 'https://www.riziv.fgov.be/'),
    ('moederschapsrust', 'Moederschapsrust', 'moederschapsrust', false, true, true, 'riziv', null, 'https://www.riziv.fgov.be/'),
    ('tijdelijke_urenvermindering', 'Tijdelijke urenvermindering (tijdskrediet)', 'tijdskrediet_variant', false, false, true, 'rva', null, 'https://www.rva.be/')
on conflict (prestatiecode) do nothing;
