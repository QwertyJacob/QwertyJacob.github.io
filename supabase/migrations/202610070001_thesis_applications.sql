-- Apply as postgres in the existing PSI project. All changes are atomic.
begin;

create table public.thesis_applications (
    id uuid primary key, -- Client-generated idempotency key; never returned by the API.
    created_at timestamptz not null default now(),
    first_name text not null check (first_name = btrim(first_name) and char_length(first_name) between 1 and 80),
    last_name text not null check (last_name = btrim(last_name) and char_length(last_name) between 1 and 80),
    email text not null check (email = lower(btrim(email)) and char_length(email) between 3 and 254
        and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
    degree_programme text not null check (degree_programme = btrim(degree_programme) and char_length(degree_programme) between 2 and 160),
    thesis_level text not null check (thesis_level = 'bachelor'),
    topics text[] not null check (cardinality(topics) between 1 and 6
        and array_position(topics, null) is null
        and topics <@ array['autumn26-a','autumn26-b','autumn26-c','autumn26-d','autumn26-e','other']::text[]),
    other_description text not null default '',
    additional_notes text not null default '' check (char_length(additional_notes) <= 3000),
    constraint thesis_other_description check (
        ('other' = any(topics) and char_length(btrim(other_description)) between 20 and 2000)
        or (not ('other' = any(topics)) and other_description = ''))
);
create index thesis_applications_email_created_idx on public.thesis_applications(email, created_at);
create index thesis_applications_created_idx on public.thesis_applications(created_at);

alter table public.thesis_applications enable row level security;
alter table public.thesis_applications force row level security;
revoke all on public.thesis_applications from public, anon, authenticated, service_role;
-- Explicit deny policy, in addition to revoked grants. No applicant SELECT policy.
create policy thesis_applications_deny_clients on public.thesis_applications
    as restrictive for all to anon, authenticated using (false) with check (false);

create function public.submit_thesis_application(
    application_id uuid,
    first_name text,
    last_name text,
    email text,
    degree_programme text,
    thesis_level text,
    topics text[],
    other_description text default '',
    additional_notes text default '',
    website text default '' -- Honeypot: not an authentication or CAPTCHA substitute.
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
    clean_email text := lower(btrim(email));
    clean_topics text[];
    existing public.thesis_applications%rowtype;
    cutoff timestamptz := clock_timestamp();
begin
    if website is distinct from '' then
        raise sqlstate 'PT400' using message = 'Invalid application.';
    end if;
    if application_id is null or first_name is null or last_name is null or email is null
       or degree_programme is null or thesis_level is distinct from 'bachelor'
       or topics is null or cardinality(topics) not between 1 and 6
       or array_ndims(topics) is distinct from 1 or array_position(topics, null) is not null
       or not (topics <@ array['autumn26-a','autumn26-b','autumn26-c','autumn26-d','autumn26-e','other']::text[])
       or char_length(btrim(first_name)) not between 1 and 80
       or char_length(btrim(last_name)) not between 1 and 80
       or char_length(clean_email) not between 3 and 254
       or clean_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       or char_length(btrim(degree_programme)) not between 2 and 160
       or other_description is null or additional_notes is null
       or char_length(additional_notes) > 3000
       or ('other' = any(topics) and char_length(btrim(other_description)) not between 20 and 2000)
       or (not ('other' = any(topics)) and other_description <> '') then
        raise sqlstate 'PT400' using message = 'Check the application fields and try again.';
    end if;
    select array_agg(t order by t) into clean_topics from (select distinct unnest(topics) as t) s;
    if cardinality(clean_topics) <> cardinality(topics) then
        raise sqlstate 'PT400' using message = 'Check the application fields and try again.';
    end if;

    -- Serialize this small form's inserts so simultaneous calls cannot evade limits.
    -- This lock is specific to theses; polls and their permissions are untouched.
    perform pg_catalog.pg_advisory_xact_lock(7262026, 1);
    select * into existing from public.thesis_applications a where a.id = application_id;
    if found then
        if existing.first_name = btrim(first_name) and existing.last_name = btrim(last_name)
           and existing.email = clean_email and existing.degree_programme = btrim(degree_programme)
           and existing.thesis_level = thesis_level and existing.topics = clean_topics
           and existing.other_description = btrim(other_description)
           and existing.additional_notes = btrim(additional_notes) then
            return; -- Retry after a lost response: no second row, no personal data returned.
        end if;
        raise sqlstate 'PT400' using message = 'This request has already been used. Reload the form.';
    end if;
    -- Same response for all budgets: do not disclose whether an email has applied.
    if exists (select 1 from public.thesis_applications a where a.email = clean_email and a.created_at > cutoff - interval '24 hours')
       or (select count(*) from public.thesis_applications a where a.created_at > cutoff - interval '1 hour') >= 30
       or (select count(*) from public.thesis_applications a where a.created_at > cutoff - interval '24 hours') >= 100 then
        raise sqlstate 'PT429' using message = 'Submissions are temporarily limited. Please try again later.';
    end if;
    insert into public.thesis_applications(id, first_name, last_name, email, degree_programme,
        thesis_level, topics, other_description, additional_notes)
    values(application_id, btrim(first_name), btrim(last_name), clean_email, btrim(degree_programme),
        thesis_level, clean_topics, btrim(other_description), btrim(additional_notes));
end;
$$;
revoke all on function public.submit_thesis_application(uuid,text,text,text,text,text,text[],text,text,text)
    from public, anon, authenticated, service_role;
grant execute on function public.submit_thesis_application(uuid,text,text,text,text,text,text[],text,text,text)
    to anon, authenticated;
comment on table public.thesis_applications is 'Private thesis applications. Admin access only; clients use the validated submission RPC.';
notify pgrst, 'reload schema';
commit;
