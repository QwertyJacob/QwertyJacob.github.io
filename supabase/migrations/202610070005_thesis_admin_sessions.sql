-- Supabase JWTs can outlive logout. Private thesis reads also require a live session.
begin;
create or replace function public.thesis_admin_access() returns boolean
language sql stable security definer set search_path = '' as $$
    select auth.uid() is not null
       and exists (select 1 from public.thesis_admins a where a.user_id = auth.uid())
       and exists (
           select 1 from auth.sessions s
           where s.user_id = auth.uid()
             and s.id::text = (auth.jwt() ->> 'session_id')
             and (s.not_after is null or s.not_after > pg_catalog.now())
       );
$$;
-- CREATE OR REPLACE preserves the restricted EXECUTE grants from migration 004.
notify pgrst, 'reload schema';
commit;
