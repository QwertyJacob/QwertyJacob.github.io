-- Run as postgres. No persistent test applications, including when assertions fail.
begin;
create function pg_temp.expect_failure(statement text, expected_state text) returns void
language plpgsql as $$
begin
    begin
        execute statement;
    exception when others then
        if sqlstate = expected_state then return; end if;
        raise exception 'Unexpected SQLSTATE %, wanted %', sqlstate, expected_state;
    end;
    raise exception 'Expected failure %', expected_state;
end;
$$;

set local role anon;
select public.submit_thesis_application('00000000-0000-4000-8000-000000000001', 'Test', 'Applicant',
    'thesis-integration-test@example.invalid', 'Computer Science', 'bachelor', array['autumn26-a','other'],
    'A sufficiently detailed alternative topic.', 'Synthetic test, rolled back.');
-- Exact retry must succeed, and must not create a second record.
select public.submit_thesis_application('00000000-0000-4000-8000-000000000001', 'Test', 'Applicant',
    'thesis-integration-test@example.invalid', 'Computer Science', 'bachelor', array['other','autumn26-a'],
    'A sufficiently detailed alternative topic.', 'Synthetic test, rolled back.');
select pg_temp.expect_failure('select * from public.thesis_applications', '42501');
select pg_temp.expect_failure('insert into public.thesis_applications(id) values(gen_random_uuid())', '42501');
select pg_temp.expect_failure('update public.thesis_applications set first_name = ''changed''', '42501');
select pg_temp.expect_failure('delete from public.thesis_applications', '42501');
select pg_temp.expect_failure('select public.submit_thesis_application(gen_random_uuid(), ''Test'', ''Applicant'', ''thesis-integration-test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a''])', 'PT429');

do $$
declare
    arguments text;
begin
    foreach arguments in array array[
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''master'', array[''autumn26-a'']',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''invalid'']',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[]::text[]',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''other''], ''Too short''',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a''], ''Unexpected description''',
        '''Test'', ''Applicant'', ''invalid'', ''CS'', ''bachelor'', array[''autumn26-a'']',
        ''' '', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a'']',
        'repeat(''x'',81), ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a'']',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a''], '''', repeat(''x'',3001)',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''other''], repeat(''x'',2001)',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a'',''autumn26-a'']',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[null]::text[]',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a''], '''', '''', ''bot''',
        '''Test'', ''Applicant'', ''test@example.invalid'', ''CS'', null, array[''autumn26-a'']'
    ] loop
        perform pg_temp.expect_failure('select public.submit_thesis_application(gen_random_uuid(), ' || arguments || ')', 'PT400');
    end loop;
end;
$$;
set local role authenticated;
select pg_temp.expect_failure('select * from public.thesis_applications', '42501');
select pg_temp.expect_failure('insert into public.thesis_applications(id) values(gen_random_uuid())', '42501');
reset role;
do $$
begin
    if (select count(*) from public.thesis_applications where id = '00000000-0000-4000-8000-000000000001') <> 1 then
        raise exception 'Idempotency failure';
    end if;
    if not (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.thesis_applications'::regclass) then
        raise exception 'RLS missing';
    end if;
end;
$$;
-- Seed synthetic quota records; all are rolled back.
insert into public.thesis_applications(id,first_name,last_name,email,degree_programme,thesis_level,topics)
select gen_random_uuid(),'Quota','Test','quota-'||n||'@example.invalid','CS','bachelor',array['autumn26-a'] from generate_series(1,30) n;
set local role anon;
select pg_temp.expect_failure('select public.submit_thesis_application(gen_random_uuid(), ''Test'', ''Applicant'', ''new@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a''])', 'PT429');
reset role;
update public.thesis_applications set created_at = now() - interval '2 hours' where email like 'quota-%@example.invalid';
insert into public.thesis_applications(id,created_at,first_name,last_name,email,degree_programme,thesis_level,topics)
select gen_random_uuid(),now()-interval '2 hours','Quota','Test','daily-'||n||'@example.invalid','CS','bachelor',array['autumn26-a'] from generate_series(1,70) n;
set local role anon;
select pg_temp.expect_failure('select public.submit_thesis_application(gen_random_uuid(), ''Test'', ''Applicant'', ''new@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a''])', 'PT429');
rollback;
