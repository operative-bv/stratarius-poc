BEGIN;
-- T-043: cascade_stap5_bijzondere_bijdragen
-- Depends: param_bijzondere_bijdragen (T-014) + T-020 seed (fso 0.10%, bev 0.16%, asbest 0.01%, loonmatiging 7.75%)

create extension if not exists pgtap;
select plan(5);

select has_function('public', 'cascade_stap5_bijzondere_bijdragen', array['numeric', 'date'], 'T1');
select is(public.cascade_stap5_bijzondere_bijdragen(4000.0000, '2024-01-01'::date), 320.8000::numeric(18,4), 'T2 grondslag 4000 × 0.0802 = 320.8000');
select is(public.cascade_stap5_bijzondere_bijdragen(0.0000, '2024-01-01'::date), 0.0000::numeric(18,4), 'T3 nul');
select is(public.cascade_stap5_bijzondere_bijdragen(4000.0000, '2023-01-01'::date), 0.0000::numeric(18,4), 'T5 temporele miss');
select is(public.cascade_stap5_bijzondere_bijdragen(4000.0000, '2024-01-01'::date), public.cascade_stap5_bijzondere_bijdragen(4000.0000, '2024-01-01'::date), 'T6 determinisme');

select * from finish();
ROLLBACK;
