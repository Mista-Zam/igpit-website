-- ===========================================================================
-- Teachers' Freedom Wall
-- 001_core_schema.sql
--
-- Tables, enums, constraints, indexes and database triggers.
--
-- Reproducible from the repository:
--   supabase db push     (linked project)
--   supabase db reset    (local stack)
--
-- Row Level Security, grants and public projections live in 002, and the
-- moderation RPCs in 003.
-- ===========================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.user_role as enum ('teacher', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.post_status as enum ('pending', 'published', 'rejected', 'removed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.post_category as enum (
    'Classroom',
    'Teaching Life',
    'Vent',
    'Wins',
    'Advice',
    'Appreciation',
    'Funny',
    'Motivation',
    'Random'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.note_color as enum (
    'yellow',
    'pink',
    'blue',
    'green',
    'lavender',
    'orange',
    'purple'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.report_reason as enum (
    'Offensive content',
    'Harassment',
    'Spam',
    'Personal information',
    'Other'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.report_status as enum ('pending', 'reviewed', 'dismissed', 'action_taken');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.moderation_action as enum (
    'approve',
    'reject',
    'remove',
    'restore',
    'resolve_report',
    'dismiss_report'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.rejection_reason as enum (
    'Inappropriate content',
    'Offensive language',
    'Harassment',
    'Spam',
    'Advertising',
    'Personal information',
    'Duplicate',
    'Other'
  );
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Shared trigger helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Database roles allowed to bypass the "immutable field" guards below.
-- These are only ever reachable from the SQL editor / service-role backends,
-- never from an end-user request (PostgREST switches to `authenticator`).
create or replace function public.is_privileged_writer()
returns boolean
language sql
stable
set search_path = ''
as $$
  select current_user in ('postgres', 'supabase_admin', 'service_role');
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  role         public.user_role not null default 'teacher',
  display_name text            not null,
  created_at   timestamptz      not null default now(),
  updated_at   timestamptz      not null default now(),

  constraint profiles_display_name_length check (char_length(display_name) between 1 and 60),
  constraint profiles_display_name_trimmed check (display_name = btrim(display_name))
);

comment on table public.profiles is
  'Teacher profiles. Display names only — email addresses are never stored or exposed here.';

create index if not exists profiles_role_idx on public.profiles (role);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- A user may edit their own display name, never their own role.
create or replace function public.profiles_guard_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.role is distinct from old.role
     and not public.is_privileged_writer() then
    new.role := old.role;
  end if;
  return new;
end;
$$;

create trigger profiles_guard_role
  before update on public.profiles
  for each row execute function public.profiles_guard_role();

-- ---------------------------------------------------------------------------
-- posts  (the sticky notes on the Freedom Wall)
-- ---------------------------------------------------------------------------

create table if not exists public.posts (
  id               uuid primary key default gen_random_uuid(),
  -- Nullable: anybody may pin a note without an account (guest submission).
  -- When set, it must point at a real profile; admins need it for moderation.
  author_id        uuid references public.profiles (id) on delete set null,
  recipient        text        not null,
  content          text        not null,
  category         public.post_category not null default 'Random',
  note_color       public.note_color    not null default 'yellow',
  is_anonymous     boolean     not null default false,
  status           public.post_status   not null default 'pending',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  reviewed_at      timestamptz,
  reviewed_by      uuid references public.profiles (id) on delete set null,
  rejection_reason public.rejection_reason,

  constraint posts_recipient_not_blank check (char_length(btrim(recipient)) between 1 and 60),
  constraint posts_recipient_trimmed    check (recipient = btrim(recipient)),
  constraint posts_content_not_blank   check (char_length(btrim(content)) between 1 and 1200),
  constraint posts_content_trimmed      check (content = btrim(content)),

  -- Moderation fields may only exist once a note has left the pending queue.
  constraint posts_review_fields_consistent check (
    (status = 'pending' and reviewed_at is null and reviewed_by is null and rejection_reason is null)
    or
    (status <> 'pending' and reviewed_at is not null)
  )
);

comment on table public.posts is
  'Sticky notes pinned to the Freedom Wall. Guests may submit without an account (author_id null). '
  'Every submission lands in ''pending''; only the moderation RPCs in 003 can change a status.';

create index if not exists posts_status_idx     on public.posts (status);
create index if not exists posts_category_idx   on public.posts (category);
create index if not exists posts_recipient_idx  on public.posts (recipient);
create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_author_idx     on public.posts (author_id);
-- Default public wall query: published notes, newest first.
create index if not exists posts_public_wall_idx on public.posts (created_at desc, id)
  where status = 'published';
-- Moderation queue: oldest submission first.
create index if not exists posts_pending_queue_idx on public.posts (created_at asc)
  where status = 'pending';

create trigger posts_set_updated_at
  before update on public.posts
  for each row execute function public.set_updated_at();

-- Belt and braces: even a client that somehow sends a status cannot publish
-- its own note. Only a privileged server-side writer (seeding / SQL editor)
-- may insert a note in any other state.
create or replace function public.posts_force_pending_on_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_privileged_writer() then
    new.status           := 'pending';
    new.reviewed_at      := null;
    new.reviewed_by      := null;
    new.rejection_reason := null;
  end if;
  return new;
end;
$$;

create trigger posts_force_pending_on_insert
  before insert on public.posts
  for each row execute function public.posts_force_pending_on_insert();

-- ---------------------------------------------------------------------------
-- reports
-- ---------------------------------------------------------------------------

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid        not null references public.posts (id) on delete cascade,
  reporter_id uuid references public.profiles (id) on delete set null,
  reason      public.report_reason not null,
  details     text,
  status      public.report_status not null default 'pending',
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id) on delete set null,

  constraint reports_details_length check (details is null or char_length(details) <= 1000),
  constraint reports_resolution_consistent check (
    (status = 'pending' and resolved_at is null and resolved_by is null)
    or
    (status <> 'pending' and resolved_at is not null)
  )
);

comment on table public.reports is
  'Community reports raised against published notes. Written and resolved through '
  'SECURITY DEFINER functions only — the table grants no direct insert/update.';

create index if not exists reports_status_idx   on public.reports (status);
create index if not exists reports_post_idx     on public.reports (post_id);
create index if not exists reports_created_idx  on public.reports (created_at desc);
create index if not exists reports_reporter_idx on public.reports (reporter_id);

-- One open report per signed-in reporter per note.
create unique index if not exists reports_one_open_per_user
  on public.reports (post_id, reporter_id)
  where reporter_id is not null and status = 'pending';

-- ---------------------------------------------------------------------------
-- moderation_logs  (append-only audit trail)
-- ---------------------------------------------------------------------------

create table if not exists public.moderation_logs (
  id                     uuid primary key default gen_random_uuid(),
  post_id                uuid references public.posts (id) on delete set null,
  moderator_id           uuid references public.profiles (id) on delete set null,
  moderator_display_name text        not null,
  post_recipient         text        not null,
  action                 public.moderation_action not null,
  reason                 text,
  previous_status        public.post_status,
  new_status             public.post_status,
  created_at             timestamptz not null default now(),

  constraint moderation_logs_reason_length check (reason is null or char_length(reason) <= 500)
);

comment on table public.moderation_logs is
  'Immutable audit trail. Denormalised snapshots (moderator_display_name, post_recipient) keep '
  'the history readable even if an account or note is later deleted.';

create index if not exists moderation_logs_post_idx    on public.moderation_logs (post_id);
create index if not exists moderation_logs_created_idx on public.moderation_logs (created_at desc);
create index if not exists moderation_logs_action_idx  on public.moderation_logs (action);
create index if not exists moderation_logs_mod_idx     on public.moderation_logs (moderator_id);

-- ---------------------------------------------------------------------------
-- Authorisation helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.profiles p
     where p.id = auth.uid()
       and p.role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated, service_role;

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.role from public.profiles p where p.id = auth.uid()),
    'teacher'::public.user_role
  );
$$;

revoke all on function public.current_user_role() from public;
grant execute on function public.current_user_role() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Profile bootstrap trigger
--
-- Creates a `teacher` profile the instant an auth user registers. The role is
-- hard-coded to 'teacher': no signup metadata payload can escalate to admin.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requested_name text;
  v_display_name   text;
begin
  v_requested_name := coalesce(new.raw_user_meta_data ->> 'display_name', '');

  if char_length(btrim(v_requested_name)) between 1 and 60 then
    v_display_name := btrim(v_requested_name);
  else
    -- Fall back to the local part of the email address, then to a default.
    v_display_name := left(
      coalesce(nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'New Teacher'),
      60
    );
  end if;

  insert into public.profiles (id, role, display_name)
  values (new.id, 'teacher', v_display_name)
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();