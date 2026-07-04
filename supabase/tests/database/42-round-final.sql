BEGIN;
-- T-025: round_final(bedrag, purpose) centrale afrondingsfunctie + private helpers
--        _round_banker_2 en _round_half_up_2.
--
-- Principe V (test-first, NON-NEGOTIABLE): dit test bestand wordt gecommit vóór
-- de migration. Bij eerste run zonder migration MOET has_function falen → Red.
--
-- Constitution Domain sectie: "Afronding gebeurt UITSLUITEND bij eindpresentatie".
-- Deze function is de instantiatie van die "expliciete afrondingsregel".
--
-- Semantiek per purpose:
--   display, report  → banker's rounding (round half to even) — DMFA-conform (KB 28/11/1969 art. 34)
--   export, invoice  → half-away-from-zero — commercial rounding voor CSV/factuur
--   unknown          → RAISE EXCEPTION SQLSTATE 22023 (invalid_parameter_value)
--
-- Fold uit plan-review round 1 (3 lenses convergeerden op silent NULL):
--   ORIGINEEL plan had `else null`; herzien naar plpgsql + RAISE om typos loud te maken.

create extension if not exists pgtap;

select plan(18);


------------------------------------------------------------
-- Function existence (T1, T2, T2b)
------------------------------------------------------------

select has_function(
    'public', 'round_final',
    array['numeric', 'text'],
    'T1: public.round_final(numeric, text) function exists'
);

select has_function(
    'public', '_round_banker_2',
    array['numeric'],
    'T2: public._round_banker_2(numeric) helper exists'
);

select has_function(
    'public', '_round_half_up_2',
    array['numeric'],
    'T2b: public._round_half_up_2(numeric) helper exists'
);


------------------------------------------------------------
-- T3, T4: Simpele niet-boundary — default purpose='display'
------------------------------------------------------------

select is(
    public.round_final(4.123),
    4.12::numeric(18, 2),
    'T3 default purpose display: 4.123 → 4.12 (niet-boundary, banker''s = half-up hier)'
);

select is(
    public.round_final(4.128, 'display'),
    4.13::numeric(18, 2),
    'T4 display niet-boundary: 4.128 → 4.13 (naar boven, geen boundary)'
);


------------------------------------------------------------
-- T5, T6, T7: Banker's boundary — positief
------------------------------------------------------------

select is(
    public.round_final(4.125, 'display'),
    4.12::numeric(18, 2),
    'T5 banker''s boundary even: 4.125 → 4.12 (2 is even → houd, NIET 4.13 zoals half-up zou doen)'
);

select is(
    public.round_final(4.135, 'display'),
    4.14::numeric(18, 2),
    'T6 banker''s boundary oneven: 4.135 → 4.14 (3 is oneven → ga naar even 4)'
);

select is(
    public.round_final(0.005, 'report'),
    0.00::numeric(18, 2),
    'T7 report == display + banker''s nul: 0.005 → 0.00 (0 is even → houd)'
);


------------------------------------------------------------
-- T8, T9: Banker's boundary — negatief (Postgres modulo sign semantics)
------------------------------------------------------------

select is(
    public.round_final(-4.125, 'display'),
    -4.12::numeric(18, 2),
    'T8 banker''s negatief boundary even: -4.125 → -4.12 (banker''s symmetrisch; -4.12 heeft even 2e decimaal 2)'
);

select is(
    public.round_final(-4.135, 'display'),
    -4.14::numeric(18, 2),
    'T9 banker''s negatief boundary oneven: -4.135 → -4.14 (2e decimaal 4 is even)'
);


------------------------------------------------------------
-- T10, T11, T12: Half-up (round-half-away-from-zero) — export/invoice
------------------------------------------------------------

select is(
    public.round_final(4.125, 'export'),
    4.13::numeric(18, 2),
    'T10 half-up export: 4.125 → 4.13 (0.5 altijd omhoog, NIET banker''s naar even)'
);

select is(
    public.round_final(4.135, 'invoice'),
    4.14::numeric(18, 2),
    'T11 half-up invoice: 4.135 → 4.14 (idem 0.5 omhoog)'
);

select is(
    public.round_final(0.005, 'export'),
    0.01::numeric(18, 2),
    'T12 half-up export nul: 0.005 → 0.01 (NIET 0.00 zoals banker''s)'
);


------------------------------------------------------------
-- T13: Divergentie-bewijs — banker's ≠ half-up voor identieke bedrag
------------------------------------------------------------

select isnt(
    public.round_final(4.125, 'display'),
    public.round_final(4.125, 'export'),
    'T13 purpose divergentie: display(4.125) ≠ export(4.125) — bewijst dat purpose enum semantisch verschil maakt'
);


------------------------------------------------------------
-- T14: Unknown purpose → RAISE EXCEPTION SQLSTATE 22023
--      (Fold uit plan-review: was silent NULL, nu fail-loud)
------------------------------------------------------------

select throws_ok(
    $sql$ select public.round_final(4.125, 'random_typo') $sql$,
    '22023',
    'round_final: unknown purpose ''random_typo''; allowed: display, report, export, invoice',
    'T14 unknown purpose raist SQLSTATE 22023 met purpose-waarde in message (fail-loud, geen silent NULL)'
);


------------------------------------------------------------
-- T14b: NULL bedrag — expliciet NULL propagation (documented behavior)
------------------------------------------------------------

select is(
    public.round_final(null::numeric, 'display'),
    null::numeric(18, 2),
    'T14b NULL bedrag → NULL (SQL null-propagation is expliciet OK voor bedrag; alleen unknown purpose raist)'
);


------------------------------------------------------------
-- T14c: Precision preservation — unbounded param voorkomt spurious boundary
--       (Fold uit error-handling lens: numeric(18,4) param cast zou 4.1250001
--        cast naar 4.1250 en spurious banker's boundary triggeren.)
------------------------------------------------------------

select is(
    public.round_final(4.1250001::numeric(18, 7), 'display'),
    4.13::numeric(18, 2),
    'T14c unbounded param: 4.1250001 → 4.13 (NIET 4.12 zoals bij (18,4)-cast; bewijst caller precisie behouden blijft)'
);


------------------------------------------------------------
-- T15a: Determinisme (2 opeenvolgende calls identiek)
------------------------------------------------------------

select is(
    public.round_final(4.125, 'display'),
    public.round_final(4.125, 'display'),
    'T15a determinisme: 2 opeenvolgende calls met identieke inputs → identieke outputs'
);


------------------------------------------------------------
-- T15b: IMMUTABLE label verificatie via pg_proc
--       (Fold clean-code lens: T15 testte determinisme, NIET IMMUTABLE.
--        Nu expliciet: pg_proc.provolatile = 'i' (immutable).)
------------------------------------------------------------

select is(
    (select provolatile from pg_proc where proname = 'round_final' and pronargs = 2),
    'i'::"char",
    'T15b IMMUTABLE label: pg_proc.provolatile = ''i'' voor round_final (Postgres optimizer-hint expliciet gedeclareerd)'
);


select * from finish();
ROLLBACK;
