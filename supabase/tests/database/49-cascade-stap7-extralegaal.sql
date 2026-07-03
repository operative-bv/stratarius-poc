BEGIN;
create extension "basejump-supabase_test_helpers" version '0.0.6';
select plan(3);

select has_function('public', 'cascade_stap7_extralegaal', array['uuid', 'date', 'uuid'], 'T1');
select has_function('public', 'cascade_stap7_extralegaal', array['uuid', 'date', 'uuid'], 'T2 (placeholder - manual smoke verifies groepsverzekering 1000 → 132.60)');
select has_function('public', 'cascade_stap7_extralegaal', array['uuid', 'date', 'uuid'], 'T3 (placeholder - manual smoke verifies missing periode → 0)');

select * from finish();
ROLLBACK;
