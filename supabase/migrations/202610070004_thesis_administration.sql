-- Read-only administration in the existing PSI project. No account/PII in migrations.
begin;

create table public.thesis_admins (
    user_id uuid primary key references auth.users(id) on delete cascade,
    granted_at timestamptz not null default now()
);
alter table public.thesis_admins enable row level security;
alter table public.thesis_admins force row level security;
revoke all on public.thesis_admins from public, anon, authenticated, service_role;
create policy thesis_admins_deny_clients on public.thesis_admins
    as restrictive for all to anon, authenticated using (false) with check (false);

create function public.thesis_admin_access() returns boolean
language sql stable security definer set search_path = '' as $$
    select auth.uid() is not null and exists (
        select 1 from public.thesis_admins a where a.user_id = auth.uid()
    );
$$;
revoke all on function public.thesis_admin_access() from public, anon, authenticated, service_role;
grant execute on function public.thesis_admin_access() to authenticated;

create index thesis_applications_arrival_id_idx on public.thesis_applications(created_at, id);
create index thesis_assignments_date_id_idx on public.thesis_topic_assignments(assigned_at, id);

-- Keyset pagination: timestamp AND UUID, plus an upper bound captured on page one.
-- Cursors retain PostgreSQL timestamp precision; clients must not round them.
create function public.thesis_admin_applications(
    after_time timestamptz default null, after_id uuid default null,
    through_time timestamptz default null, through_id uuid default null,
    page_size integer default 20
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
    result jsonb;
begin
    if not public.thesis_admin_access() then
        raise sqlstate 'PT403' using message = 'Administrator access required.';
    end if;
    if page_size is null or page_size not between 1 and 100
       or (after_time is null) <> (after_id is null)
       or (through_time is null) <> (through_id is null)
       or (after_id is not null and through_id is null) then
        raise sqlstate 'PT400' using message = 'Invalid page cursor.';
    end if;
    if through_id is null then
        select a.created_at, a.id into through_time, through_id
        from public.thesis_applications a order by a.created_at desc, a.id desc limit 1;
    end if;
    with candidates as (
        select a.* from public.thesis_applications a
        where (after_id is null or (a.created_at, a.id) > (after_time, after_id))
          and (a.created_at, a.id) <= (through_time, through_id)
        order by a.created_at asc, a.id asc limit page_size + 1
    ), page as (
        select * from candidates order by created_at asc, id asc limit page_size
    ) select pg_catalog.jsonb_build_object(
        'rows', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) order by p.created_at, p.id) from page p), '[]'::jsonb),
        'has_more', (select count(*) > page_size from candidates),
        'next_cursor', (select pg_catalog.jsonb_build_object('time', p.created_at, 'id', p.id) from page p order by p.created_at desc, p.id desc limit 1),
        'snapshot', case when through_id is null then null else pg_catalog.jsonb_build_object('time', through_time, 'id', through_id) end
    ) into result;
    return result;
end;
$$;

create function public.thesis_admin_assignments(
    after_time timestamptz default null, after_id uuid default null,
    through_time timestamptz default null, through_id uuid default null,
    page_size integer default 20
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
    result jsonb;
begin
    if not public.thesis_admin_access() then
        raise sqlstate 'PT403' using message = 'Administrator access required.';
    end if;
    if page_size is null or page_size not between 1 and 100
       or (after_time is null) <> (after_id is null)
       or (through_time is null) <> (through_id is null)
       or (after_id is not null and through_id is null) then
        raise sqlstate 'PT400' using message = 'Invalid page cursor.';
    end if;
    if through_id is null then
        select a.assigned_at, a.id into through_time, through_id
        from public.thesis_topic_assignments a order by a.assigned_at desc, a.id desc limit 1;
    end if;
    with candidates as (
        select a.id, a.assigned_at, a.topic_id, a.first_name, a.last_name,
               a.email, a.degree_programme, a.other_description, a.application_id,
               application.created_at as application_arrived_at
        from public.thesis_topic_assignments a
        left join public.thesis_applications application on application.id = a.application_id
        where (after_id is null or (a.assigned_at, a.id) > (after_time, after_id))
          and (a.assigned_at, a.id) <= (through_time, through_id)
        order by a.assigned_at asc, a.id asc limit page_size + 1
    ), page as (
        select * from candidates order by assigned_at asc, id asc limit page_size
    ) select pg_catalog.jsonb_build_object(
        'rows', coalesce((select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) order by p.assigned_at, p.id) from page p), '[]'::jsonb),
        'has_more', (select count(*) > page_size from candidates),
        'next_cursor', (select pg_catalog.jsonb_build_object('time', p.assigned_at, 'id', p.id) from page p order by p.assigned_at desc, p.id desc limit 1),
        'snapshot', case when through_id is null then null else pg_catalog.jsonb_build_object('time', through_time, 'id', through_id) end
    ) into result;
    return result;
end;
$$;
revoke all on function public.thesis_admin_applications(timestamptz,uuid,timestamptz,uuid,integer)
    from public, anon, authenticated, service_role;
revoke all on function public.thesis_admin_assignments(timestamptz,uuid,timestamptz,uuid,integer)
    from public, anon, authenticated, service_role;
grant execute on function public.thesis_admin_applications(timestamptz,uuid,timestamptz,uuid,integer) to authenticated;
grant execute on function public.thesis_admin_assignments(timestamptz,uuid,timestamptz,uuid,integer) to authenticated;
-- Existing applicant-deny policies and table grants are deliberately untouched.
notify pgrst, 'reload schema';
commit;
