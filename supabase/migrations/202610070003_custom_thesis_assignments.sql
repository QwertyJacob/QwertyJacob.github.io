-- Support multiple confirmed custom theses without closing the Other form option.
-- No student details belong in migration files.
begin;
select pg_catalog.pg_advisory_xact_lock(7262026, 1);
alter table public.thesis_topic_assignments
    add column id uuid not null default gen_random_uuid(),
    add column other_description text not null default '',
    drop constraint thesis_topic_assignments_pkey,
    drop constraint thesis_topic_assignments_topic_id_check;
alter table public.thesis_topic_assignments
    add primary key (id),
    add constraint thesis_assignment_other_description check (
        (topic_id = 'other' and char_length(btrim(other_description)) between 20 and 2000)
        or (topic_id <> 'other' and other_description = ''));
create unique index thesis_topic_single_assignment_idx
    on public.thesis_topic_assignments(topic_id) where topic_id <> 'other';

create or replace function public.thesis_topic_availability()
returns table(topic_id text, available boolean)
language sql stable security definer set search_path = '' as $$
    select topic.id, topic.id = 'other' or not exists (
        select 1 from public.thesis_topic_assignments assignment where assignment.topic_id = topic.id
    ) from public.thesis_topics topic order by topic.id;
$$;

create or replace function public.submit_thesis_application(
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
    if exists (select 1 from public.thesis_topic_assignments assignment
               where assignment.topic_id <> 'other' and assignment.topic_id = any(clean_topics)) then
        raise sqlstate 'PT409' using message = 'A selected topic is no longer available. Please choose another topic.';
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
notify pgrst, 'reload schema';
commit;
