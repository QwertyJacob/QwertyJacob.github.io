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
insert into public.thesis_topic_assignments(topic_id,first_name,last_name)
values('autumn26-a','Synthetic','Assignment');
-- Multiple custom assignments are private and do not consume the Other option.
insert into public.thesis_topic_assignments(topic_id,first_name,last_name,other_description) values
    ('other','Synthetic','Custom one','A sufficiently detailed first custom thesis.'),
    ('other','Synthetic','Custom two','A sufficiently detailed second custom thesis.');
select pg_temp.expect_failure('insert into public.thesis_topic_assignments(topic_id,first_name,last_name) values(''other'',''Synthetic'',''Missing description'')', '23514');
select pg_temp.expect_failure('insert into public.thesis_topic_assignments(topic_id,first_name,last_name) values(''autumn26-a'',''Synthetic'',''Duplicate'')', '23505');
set local role anon;
select public.submit_thesis_application(gen_random_uuid(),'Synthetic','Custom application',
    'custom-availability-test@example.invalid','CS','bachelor',array['other'],
    'Another custom thesis can still be requested.');
select pg_temp.expect_failure('select * from public.thesis_topic_assignments', '42501');
select pg_temp.expect_failure('select * from public.thesis_topics', '42501');
select pg_temp.expect_failure('delete from public.thesis_topic_assignments', '42501');
do $$
declare
    row_count int;
begin
    select count(*) into row_count from public.thesis_topic_availability();
    if row_count <> 6 then raise exception 'Wrong number of availability rows'; end if;
    if (select available from public.thesis_topic_availability() where topic_id='autumn26-a') then
        raise exception 'Assigned topic still available';
    end if;
    if not (select available from public.thesis_topic_availability() where topic_id='other') then
        raise exception 'Other should remain available';
    end if;
end;
$$;
select pg_temp.expect_failure('select public.submit_thesis_application(gen_random_uuid(), ''Synthetic'', ''Test'', ''availability-test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a''])', 'PT409');
select pg_temp.expect_failure('select public.submit_thesis_application(gen_random_uuid(), ''Synthetic'', ''Test'', ''availability-test@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-a'',''autumn26-e''])', 'PT409');
select public.submit_thesis_application('00000000-0000-4000-8000-000000000002','Synthetic','Retry',
    'availability-retry@example.invalid','CS','bachelor',array['autumn26-b']);
reset role;
insert into public.thesis_topic_assignments(topic_id,first_name,last_name)
values('autumn26-b','Synthetic','Assigned after submission');
set local role anon;
-- A successful application's retry remains idempotent even after allocation.
select public.submit_thesis_application('00000000-0000-4000-8000-000000000002','Synthetic','Retry',
    'availability-retry@example.invalid','CS','bachelor',array['autumn26-b']);
set local role authenticated;
select pg_temp.expect_failure('select * from public.thesis_topic_assignments', '42501');
select pg_temp.expect_failure('insert into public.thesis_topic_assignments(topic_id,first_name,last_name) values(''autumn26-e'',''Fake'',''Assignment'')', '42501');
select pg_temp.expect_failure('select public.submit_thesis_application(gen_random_uuid(), ''Synthetic'', ''Test'', ''availability-other@example.invalid'', ''CS'', ''bachelor'', array[''autumn26-b''])', 'PT409');
rollback;
