-- Every synthetic record and privilege change is rolled back.
begin;
create function pg_temp.admin_expect_failure(statement text, expected_state text) returns void
language plpgsql as $$
begin
    begin execute statement;
    exception when others then
        if sqlstate = expected_state then return; end if;
        raise exception 'Unexpected SQLSTATE %, wanted %', sqlstate, expected_state;
    end;
    raise exception 'Expected failure %', expected_state;
end;
$$;
insert into auth.users(id, aud, role, email) values
    ('00000000-0000-4000-9000-000000000001','authenticated','authenticated','admin-fixture@example.invalid');
insert into public.thesis_admins(user_id) values ('00000000-0000-4000-9000-000000000001');
insert into auth.sessions(id,user_id) values
    ('00000000-0000-4000-9300-000000000001','00000000-0000-4000-9000-000000000001');
insert into public.thesis_applications(id,created_at,first_name,last_name,email,degree_programme,thesis_level,topics,other_description,additional_notes)
select ('00000000-0000-4000-9100-' || lpad(i::text,12,'0'))::uuid,
    case when i < 3 then '1900-01-01T00:00:00.123456Z'::timestamptz else '1900-01-02Z'::timestamptz end,
    '<img src=x onerror=alert(1)>','Synthetic', 'admin-test-' || i || '@example.invalid',
    'CS','bachelor',array['other'],'A sufficiently detailed synthetic topic.', '<script>alert(1)</script>'
from generate_series(1,3) i;
insert into public.thesis_topic_assignments(id,assigned_at,topic_id,first_name,last_name,other_description,application_id)
values ('00000000-0000-4000-9200-000000000001','1900-01-03Z','other','Synthetic','Assignment',
    'A separate confirmed custom thesis assignment.','00000000-0000-4000-9100-000000000001');

set local role anon;
select pg_temp.admin_expect_failure('select public.thesis_admin_access()', '42501');
select pg_temp.admin_expect_failure('select public.thesis_admin_applications()', '42501');
select pg_temp.admin_expect_failure('select public.thesis_admin_assignments()', '42501');
select pg_temp.admin_expect_failure('select * from public.thesis_admins', '42501');
select pg_temp.admin_expect_failure('select * from public.thesis_applications', '42501');
select pg_temp.admin_expect_failure('select * from public.thesis_topic_assignments', '42501');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-9000-000000000002","role":"authenticated"}',true);
do $$ begin
    if public.thesis_admin_access() then raise exception 'Non-admin authorized'; end if;
end; $$;
select pg_temp.admin_expect_failure('select public.thesis_admin_applications()', 'PT403');
select pg_temp.admin_expect_failure('select public.thesis_admin_assignments()', 'PT403');
select pg_temp.admin_expect_failure('select * from public.thesis_applications', '42501');
select pg_temp.admin_expect_failure('select * from public.thesis_topic_assignments', '42501');
select pg_temp.admin_expect_failure('insert into public.thesis_admins(user_id) values(auth.uid())', '42501');

-- An allowlisted UUID alone, without a live owned Auth session, must fail.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-9000-000000000001","role":"authenticated"}',true);
select pg_temp.admin_expect_failure('select public.thesis_admin_applications()', 'PT403');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-9000-000000000002","role":"authenticated","session_id":"00000000-0000-4000-9300-000000000001"}',true);
select pg_temp.admin_expect_failure('select public.thesis_admin_assignments()', 'PT403');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-9000-000000000001","role":"authenticated","session_id":"00000000-0000-4000-9300-000000000001"}',true);
select pg_temp.admin_expect_failure('select * from public.thesis_applications', '42501');
select pg_temp.admin_expect_failure('select * from public.thesis_topic_assignments', '42501');
select pg_temp.admin_expect_failure('select * from public.thesis_admins', '42501');
select pg_temp.admin_expect_failure('delete from public.thesis_applications', '42501');
select pg_temp.admin_expect_failure('update public.thesis_topic_assignments set first_name=''changed''', '42501');
select pg_temp.admin_expect_failure('select public.thesis_admin_applications(page_size=>0)', 'PT400');
select pg_temp.admin_expect_failure('select public.thesis_admin_assignments(page_size=>101)', 'PT400');
select pg_temp.admin_expect_failure('select public.thesis_admin_applications(after_id=>gen_random_uuid())', 'PT400');
select pg_temp.admin_expect_failure('select public.thesis_admin_applications(after_time=>now(),after_id=>gen_random_uuid())', 'PT400');

create temporary table admin_test_pages(first_page jsonb, assignments jsonb);
insert into admin_test_pages values(public.thesis_admin_applications(page_size=>2),public.thesis_admin_assignments(page_size=>1));
do $$
declare p jsonb; a jsonb;
begin
    select first_page, assignments into p,a from admin_test_pages;
    if not public.thesis_admin_access() or jsonb_array_length(p->'rows') <> 2 or not (p->>'has_more')::boolean
       or p#>>'{rows,0,id}' <> '00000000-0000-4000-9100-000000000001'
       or p#>>'{rows,1,id}' <> '00000000-0000-4000-9100-000000000002'
       or p#>>'{next_cursor,time}' <> '1900-01-01T00:00:00.123456+00:00' then
        raise exception 'Admin ordering, tie-break or timestamp precision failed';
    end if;
    if a#>>'{rows,0,id}' <> '00000000-0000-4000-9200-000000000001'
       or (a#>>'{rows,0,assigned_at}')::timestamptz = (a#>>'{rows,0,application_arrived_at}')::timestamptz then
        raise exception 'Assignment/application dates mixed';
    end if;
end;
$$;
reset role;
insert into public.thesis_applications(id,created_at,first_name,last_name,email,degree_programme,thesis_level,topics,other_description)
values('00000000-0000-4000-9100-000000000004','2999-01-01Z','Later','Synthetic','later@example.invalid','CS','bachelor',array['other'],'A later synthetic custom thesis proposal.');
-- Removing a previously read row must not shift subsequent keyset pages.
delete from public.thesis_applications where id='00000000-0000-4000-9100-000000000002';
set local role authenticated;
do $$
declare p jsonb; next_page jsonb;
begin
    select first_page into p from admin_test_pages;
    next_page := public.thesis_admin_applications(
        (p#>>'{next_cursor,time}')::timestamptz, (p#>>'{next_cursor,id}')::uuid,
        (p#>>'{snapshot,time}')::timestamptz, (p#>>'{snapshot,id}')::uuid, 100);
    if next_page#>>'{rows,0,id}' <> '00000000-0000-4000-9100-000000000003'
       or exists(select 1 from jsonb_array_elements(next_page->'rows') r where r->>'id'='00000000-0000-4000-9100-000000000004') then
        raise exception 'Keyset pagination skipped/duplicated rows or lost its upper bound';
    end if;
    if public.thesis_admin_applications(through_time=>'1800-01-01Z',through_id=>'00000000-0000-4000-9100-000000000001')->'rows' <> '[]'::jsonb then
        raise exception 'Empty page failed';
    end if;
end;
$$;
reset role;
-- Session revocation/expiry blocks further reads even before the JWT expires.
update auth.sessions set not_after=now()-interval '1 second' where id='00000000-0000-4000-9300-000000000001';
set local role authenticated;
select pg_temp.admin_expect_failure('select public.thesis_admin_applications()', 'PT403');
reset role;
delete from auth.sessions where id='00000000-0000-4000-9300-000000000001';
set local role authenticated;
select pg_temp.admin_expect_failure('select public.thesis_admin_assignments()', 'PT403');
reset role;
insert into auth.sessions(id,user_id) values
    ('00000000-0000-4000-9300-000000000001','00000000-0000-4000-9000-000000000001');
delete from public.thesis_admins where user_id='00000000-0000-4000-9000-000000000001';
set local role authenticated;
select pg_temp.admin_expect_failure('select public.thesis_admin_applications()', 'PT403');
select pg_temp.admin_expect_failure('select public.thesis_admin_assignments()', 'PT403');
-- Even accidental SELECT grants cannot override the existing restrictive denies.
reset role;
grant select on public.thesis_applications, public.thesis_topic_assignments, public.thesis_admins to authenticated;
set local role authenticated;
do $$ begin
    if exists(select 1 from public.thesis_applications) or exists(select 1 from public.thesis_topic_assignments)
       or exists(select 1 from public.thesis_admins) then raise exception 'Restrictive deny weakened'; end if;
end; $$;
rollback;
