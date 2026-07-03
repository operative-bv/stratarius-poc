BEGIN;
create extension "basejump-supabase_test_helpers" version '0.0.6';
select plan(4);

select has_function('public', 'cascade_stap6_vakantiegeld', array['numeric', 'text', 'date'], 'T1');
select is(public.cascade_stap6_vakantiegeld(4000.0000, 'arbeider', '2024-01-01'::date), 615.2000::numeric(18,4), 'T2 arbeider 4000 × 0.1538 = 615.20');
select is(public.cascade_stap6_vakantiegeld(4000.0000, 'bediende', '2024-01-01'::date), 3986.8000::numeric(18,4), 'T3 bediende 4000 × (0.0767 + 0.92) = 3986.80');
select is(public.cascade_stap6_vakantiegeld(4000.0000, 'arbeider', '2023-01-01'::date), null::numeric(18,4), 'T4 temporele miss → NULL');

select * from finish();
ROLLBACK;
