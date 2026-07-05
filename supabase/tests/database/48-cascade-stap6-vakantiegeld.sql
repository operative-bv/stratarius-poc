BEGIN;
-- Function normaliseert naar per-maand provisie (jaar-annualized / 12) voor
-- cascade output consistency. Expected values dus jaar-formule / 12.
create extension if not exists pgtap;
select plan(4);

select has_function('public', 'cascade_stap6_vakantiegeld', array['numeric', 'text', 'date'], 'T1');
select is(public.cascade_stap6_vakantiegeld(4000.0000, 'arbeider', '2024-01-01'::date), 51.2667::numeric(18,4), 'T2 arbeider: (4000 × 0.1538) / 12 = 51.2667 per-maand');
select is(public.cascade_stap6_vakantiegeld(4000.0000, 'bediende', '2024-01-01'::date), 332.2333::numeric(18,4), 'T3 bediende: (4000 × (0.0767 + 0.92)) / 12 = 332.2333 per-maand');
select is(public.cascade_stap6_vakantiegeld(4000.0000, 'arbeider', '2023-01-01'::date), null::numeric(18,4), 'T4 temporele miss → NULL');

select * from finish();
ROLLBACK;
