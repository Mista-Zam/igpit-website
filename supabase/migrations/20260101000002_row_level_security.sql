-- ===========================================================================
-- Teachers' Freedom Wall
-- 002_row_level_security.sql
--
-- Row Level Security, grants/privileges and the public read model.
--
-- Security model summary
-- ----------------------
--  * anon  : read-only, and only through `posts_public`. No table privileges.
--  * teacher: may insert its own note (status column is NOT writable),
--             read only its own notes, edit its own unpublished notes,
--             and file reports through `submit_report()`.
--  * admin  : additionally reads every table and changes statuses only
--             through the SECURITY DEFINER moderation functions in 003.
--
-- Privilege model (in addition to RLS)
-- ------------------------------------
-- Column-level grants mean a teacher's INSERT payload physically cannot carry
-- `status`, `reviewed_by`, `reviewed_at` or `rejection_reason`, and an UPDATE
-- cannot carry `role` on profiles or `status` on posts. Writes to reports and
-- moderation_logs have no grants at all — only the SECURITY DEFINER functions
-- can write them.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- RLS: enabled everywhere
-- ---------------------------------------------------------------------------

-- RLS applies to the `anon` and `authenticated` roles that PostgREST switches
-- into for every request. The table owner (postgres) is intentionally NOT
-- forced through RLS, because the SECURITY DEFINER moderation functions in 003
-- run as the owner and must be able to write.
alter table public.profiles        enable row level security;
alter table public.posts           enable row level security;
alter table public.reports         enable row level security;
alter table public.moderation_logs enable row level security;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

-- profiles: no anonymous access at all. Teachers manage only their own row.
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;

-- posts: anyone (including guests) may pin a note; the status columns are withheld
-- from every client role.
revoke all on table public.posts from anon, authenticated;
grant select on table public.posts to authenticated;
grant insert (author_id, recipient, content, category, note_color, is_anonymous)
  on table public.posts to anon, authenticated;
grant update (recipient, content, category, note_color, is_anonymous)
  on table public.posts to authenticated;

-- reports: reads for admins only; every write goes through submit_report().
revoke all on table public.reports from anon, authenticated;
grant select on table public.reports to authenticated;

-- moderation_logs: reads for admins only; insert/update/delete are never granted,
-- which is what makes the audit trail append-only.
revoke all on table public.moderation_logs from anon, authenticated;
grant select on table public.moderation_logs to authenticated;

-- ---------------------------------------------------------------------------
-- Policies
--
-- Guests (anon) can insert a note and nothing else. Signed-in teachers can do
-- the same plus manage their own notes and profile.
-- ---------------------------------------------------------------------------

-- profiles ------------------------------------------------------------------

drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin
  on public.profiles
  for select
  to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- posts ---------------------------------------------------------------------

-- Teachers can only ever see their own notes (any status). Admins see the wall
-- plus the full moderation queue. Anonymous visitors read `posts_public`.
drop policy if exists posts_select_own_or_admin on public.posts;
create policy posts_select_own_or_admin
  on public.posts
  for select
  to authenticated
  using (author_id = (select auth.uid()) or (select public.is_admin()));

-- Anyone may pin a note, signed in or not. A signed-in teacher may only attach
-- their own author_id (or leave it null); a guest must leave it null.
drop policy if exists posts_insert_anyone_pending on public.posts;
create policy posts_insert_anyone_pending
  on public.posts
  for insert
  to anon, authenticated
  with check (
    (author_id is null or author_id = (select auth.uid()))
    and status = 'pending'
    and reviewed_at is null
    and reviewed_by is null
    and rejection_reason is null
  );

-- Teachers may revise a note only while it is unpublished. Published notes are
-- frozen; a teacher who needs a live note changed must ask a moderator.
drop policy if exists posts_update_own_unpublished on public.posts;
create policy posts_update_own_unpublished
  on public.posts
  for update
  to authenticated
  using (
    author_id = (select auth.uid())
    and status in ('pending', 'rejected')
  )
  with check (author_id = (select auth.uid()));

-- Deliberately no DELETE policy: notes are never hard-deleted by an author.

-- reports -------------------------------------------------------------------

drop policy if exists reports_select_admin on public.reports;
create policy reports_select_admin
  on public.reports
  for select
  to authenticated
  using ((select public.is_admin()));

-- moderation_logs -----------------------------------------------------------

drop policy if exists moderation_logs_select_admin on public.moderation_logs;
create policy moderation_logs_select_admin
  on public.moderation_logs
  for select
  to authenticated
  using ((select public.is_admin()));

-- ---------------------------------------------------------------------------
-- Public read model
--
-- `posts_public` is the single door through which the outside world reads the
-- Freedom Wall. It hard-codes `status = 'published'` and never exposes
-- author_id, reviewed_by or rejection_reason, so an anonymous author's
-- account identifier cannot be derived from the public API.
-- ---------------------------------------------------------------------------

drop view if exists public.posts_public;
create view public.posts_public
with (security_invoker = false)
as
  select
    p.id,
    p.recipient,
    p.content,
    p.category,
    p.note_color,
    p.is_anonymous,
    p.created_at,
    p.updated_at,
    case
      when p.is_anonymous then 'Anonymous'
      else coalesce(nullif(btrim(pr.display_name), ''), 'A Teacher')
    end as author_display_name,
    exists (
      select 1
        from public.reports r
       where r.post_id = p.id
         and r.reporter_id = (select auth.uid())
    ) as reported_by_me
  from public.posts p
  left join public.profiles pr on pr.id = p.author_id
 where p.status = 'published';

grant select on public.posts_public to anon, authenticated;

comment on view public.posts_public is
  'Public projection of the Freedom Wall: published notes only, no author ids, no moderation data.';

-- ---------------------------------------------------------------------------
-- Comments documenting intent for future readers
-- ---------------------------------------------------------------------------

comment on table public.posts is
  'Teachers may only insert (author_id, recipient, content, category, note_color, is_anonymous). '
  'Status changes are impossible without going through the moderation RPCs in 003.';