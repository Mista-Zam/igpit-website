-- ===========================================================================
-- Teachers' Freedom Wall
-- supabase/tests/security_checks.sql
--
-- Executable verification of the security model described in the brief.
-- Every check asserts real database behaviour under the `anon`,
-- `authenticated` (teacher) and admin roles.
--
-- How to run (against a scratch database, as the `postgres` role):
--
--   supabase db push
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/security_checks.sql
--
-- The script is self-contained: it builds its own fixtures, asserts, and prints
-- a summary. It expects migrations 001-003 to have been applied.
--
-- WARNING: it truncates application tables. Never point it at production.
-- ===========================================================================

\set ON_ERROR_STOP on
\timing off

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

create temp table sec_results (
  seq    serial primary key,
  label  text not null,
  ok     boolean not null,
  detail text
);

-- Run a statement as an API role with a given auth.uid().
-- Returns NULL on success, otherwise the error message.
create or replace function pg_temp.run_as(p_role text, p_uid uuid, p_stmt text)
returns text
language plpgsql
as $$
declare
  v_err text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    perform set_config('role', p_role, true);
    execute p_stmt;
    perform set_config('role', 'none', true);
    return null;
  exception when others then
    v_err := sqlerrm;
    begin
      perform set_config('role', 'none', true);
    exception when others then
      null;
    end;
    return v_err;
  end;
end;
$$;

-- Run `select count(*) from (<query>) t` as a given role. -1 means "refused".
create or replace function pg_temp.count_as(p_role text, p_uid uuid, p_query text)
returns bigint
language plpgsql
as $$
declare
  v_count bigint;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('role', p_role, true);
  execute 'select count(*) from (' || p_query || ') t' into v_count;
  perform set_config('role', 'none', true);
  return v_count;
exception when others then
  begin
    perform set_config('role', 'none', true);
  exception when others then
    null;
  end;
  return -1;
end;
$$;

-- How many rows did a statement actually change, as a given role?
create or replace function pg_temp.affected_as(p_role text, p_uid uuid, p_stmt text)
returns bigint
language plpgsql
as $$
declare
  v_count bigint := 0;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('role', p_role, true);
  execute p_stmt;
  get diagnostics v_count = row_count;
  perform set_config('role', 'none', true);
  return v_count;
exception when others then
  begin
    perform set_config('role', 'none', true);
  exception when others then
    null;
  end;
  return -1;
end;
$$;

create or replace function pg_temp.expect_ok(p_label text, p_role text, p_uid uuid, p_stmt text)
returns void
language plpgsql
as $$
declare v_err text;
begin
  v_err := pg_temp.run_as(p_role, p_uid, p_stmt);
  insert into sec_results (label, ok, detail)
  values (p_label, v_err is null, coalesce(v_err, 'succeeded'));
end;
$$;

create or replace function pg_temp.expect_denied(p_label text, p_role text, p_uid uuid, p_stmt text)
returns void
language plpgsql
as $$
declare v_err text;
begin
  v_err := pg_temp.run_as(p_role, p_uid, p_stmt);
  insert into sec_results (label, ok, detail)
  values (p_label, v_err is not null, coalesce(v_err, 'UNEXPECTEDLY ALLOWED'));
end;
$$;

create or replace function pg_temp.expect_rows(p_label text, p_role text, p_uid uuid, p_stmt text, p_expected bigint)
returns void
language plpgsql
as $$
declare v_n bigint;
begin
  v_n := pg_temp.affected_as(p_role, p_uid, p_stmt);
  insert into sec_results (label, ok, detail)
  values (p_label, v_n = p_expected, format('%s row(s) changed, expected %s', v_n, p_expected));
end;
$$;

create or replace function pg_temp.expect_count(p_label text, p_role text, p_uid uuid, p_query text, p_expected bigint)
returns void
language plpgsql
as $$
declare v_n bigint;
begin
  v_n := pg_temp.count_as(p_role, p_uid, p_query);
  insert into sec_results (label, ok, detail)
  values (p_label, v_n = p_expected, format('%s row(s), expected %s', v_n, p_expected));
end;
$$;

create or replace function pg_temp.check(p_label text, p_ok boolean, p_detail text default '')
returns void
language plpgsql
as $$
begin
  insert into sec_results (label, ok, detail) values (p_label, p_ok, p_detail);
end;
$$;

-- Resolve a note id as the table owner, so a check can name a note even when
-- the calling role is not allowed to see that row. Without this, a sub-select
-- inside a check would itself be filtered by RLS and return NULL.
create or replace function pg_temp.note_id(p_recipient text)
returns uuid
language plpgsql
security definer
as $$
declare
  v_ids  uuid[];
  v_count integer;
begin
  select array_agg(id), count(*) into v_ids, v_count
    from public.posts where recipient = p_recipient;

  if v_count = 0 then
    raise exception 'no fixture note addressed to %', p_recipient;
  end if;
  if v_count > 1 then
    raise exception 'fixture recipient % is ambiguous (% notes)', p_recipient, v_count;
  end if;

  return v_ids[1];
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

truncate table public.reports, public.moderation_logs, public.posts, public.profiles restart identity cascade;
delete from auth.users;

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'teacher.a@example.test',
     '{"display_name":"Ms. Alvarez","role":"admin","is_admin":true}'),
  ('22222222-2222-4222-8222-222222222222', 'teacher.b@example.test',
     '{"display_name":"Mr. Okafor"}'),
  ('33333333-3333-4333-8333-333333333333', 'moderator@example.test',
     '{"display_name":"Ms. Admin"}');

-- A. Signup cannot escalate to admin, even when the metadata asks for it.

select pg_temp.check(
  'A1 signup always creates a profile',
  (select count(*) = 3 from public.profiles),
  format('%s profile(s) created', (select count(*) from public.profiles))
);

select pg_temp.check(
  'A2 malicious role in signup metadata is ignored',
  (select count(*) = 0 from public.profiles where role = 'admin'),
  format('%s admin profile(s)', (select count(*) from public.profiles where role = 'admin'))
);

select pg_temp.check(
  'A3 display name from signup metadata is used',
  (select display_name = 'Ms. Alvarez' from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'),
  ''
);

-- Promote the moderator (simulates the documented SQL-editor step).
update public.profiles
   set role = 'admin'
 where id = '33333333-3333-4333-8333-333333333333';

-- Teacher A pins two notes, teacher B pins one.
insert into public.posts (author_id, recipient, content, category, note_color, is_anonymous)
values
  ('11111111-1111-4111-8111-111111111111', 'Mrs. Thornbull',
     'Thank you for always checking on us.', 'Appreciation', 'yellow', true),
  ('11111111-1111-4111-8111-111111111111', 'Sir Daniel',
   'That one joke during the faculty meeting saved my Monday.', 'Funny', 'pink', false),
  ('11111111-1111-4111-8111-111111111111', 'Mrs. Santos',
   'Your students may not say it often, but they notice how much effort you put in.',
   'Appreciation', 'lavender', false);

insert into public.posts (author_id, recipient, content, category, note_color, is_anonymous)
values
  ('22222222-2222-4222-8222-222222222222', 'All Teachers',
   'Some days we teach. Some days we survive. Both count.', 'Motivation', 'green', false);

-- Moderator approves the anonymous note.
do $$
begin
  perform set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
  perform public.admin_moderate_post(
    (select id from public.posts where recipient = 'Mrs. Thornbull'),
    'approve'
  );
end;
$$;



-- ---------------------------------------------------------------------------
-- B. Guests (anon) â€” can pin a note, can do nothing else
-- ---------------------------------------------------------------------------

select pg_temp.expect_ok('B1 guest can pin a note without an account', 'anon', null,
  $q$insert into public.posts (author_id, recipient, content, category, note_color, is_anonymous)
    values (null, 'Mr. Osei', 'You made my first semester here feel less scary.', 'Appreciation', 'blue', true)$q$);

select pg_temp.check(
  'B2 guest note lands in pending',
  exists (select 1 from public.posts where recipient = 'Mr. Osei' and status = 'pending'
            and author_id is null),
  ''
);

select pg_temp.expect_denied('B3 guest cannot submit a published note', 'anon', null,
  $q$insert into public.posts (author_id, recipient, content, status)
    values (null, 'Sneaky', 'Publish me', 'published')$q$);

select pg_temp.expect_denied('B4 guest cannot impersonate an author id', 'anon', null,
  $q$insert into public.posts (author_id, recipient, content)
    values ('11111111-1111-4111-8111-111111111111', 'Not mine', 'Hijack')$q$);

select pg_temp.expect_denied('B5 guest cannot read the posts table', 'anon', null,
  'select * from public.posts');

select pg_temp.expect_denied('B6 guest cannot read reports', 'anon', null,
  'select * from public.reports');

select pg_temp.expect_denied('B7 guest cannot read moderation logs', 'anon', null,
  'select * from public.moderation_logs');

select pg_temp.expect_denied('B8 guest cannot read profiles', 'anon', null,
  'select * from public.profiles');

select pg_temp.expect_denied('B9 guest cannot edit a note', 'anon', null,
  $q$update public.posts set content = 'tampered' where id = '11111111-1111-4111-8111-111111111111'$q$);

select pg_temp.expect_ok('B10 guest can read the public wall view', 'anon', null,
  'select * from public.posts_public');

select pg_temp.check(
  'B11 public wall shows published notes only',
  (select count(*) = 1 from public.posts_public),
  format('%s visible', (select count(*) from public.posts_public))
);

select pg_temp.check(
  'B12 public wall exposes no author ids or moderation data',
  not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'posts_public'
       and column_name in ('author_id', 'reviewed_by', 'reviewed_at',
                           'rejection_reason', 'status')
  ),
  ''
);

select pg_temp.check(
  'B13 anonymous note never exposes the author account',
  (select author_display_name = 'Anonymous' from public.posts_public
    where recipient = 'Mrs. Thornbull')
  and (select count(*) = 1 from public.posts_public where recipient = 'Mrs. Thornbull'),
  ''
);

select pg_temp.expect_ok('B14 guest can report a published note', 'anon', null,
  $q$select public.submit_report((select pg_temp.note_id('Mrs. Thornbull')), 'Spam', 'looks like spam')$q$);

-- ---------------------------------------------------------------------------
-- C. Teacher (authenticated, role = teacher)
-- ---------------------------------------------------------------------------

select pg_temp.expect_ok('C1 teacher can pin a note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$insert into public.posts (author_id, recipient, content, category, note_color)
    values ('11111111-1111-4111-8111-111111111111', 'Ms. Reyes',
            'You made my first semester here feel less scary.', 'Appreciation', 'blue')$q$);

select pg_temp.check(
  'C2 new notes are pending, never published',
  exists (select 1 from public.posts where recipient = 'Ms. Reyes' and status = 'pending'),
  ''
);

select pg_temp.expect_denied('C3 teacher cannot submit a published note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$insert into public.posts (author_id, recipient, content, status)
    values ('11111111-1111-4111-8111-111111111111', 'Sneaky', 'Publish me', 'published')$q$);

select pg_temp.expect_denied('C4 teacher cannot post as another author', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$insert into public.posts (author_id, recipient, content)
    values ('22222222-2222-4222-8222-222222222222', 'Not mine', 'Hijack')$q$);

select pg_temp.expect_denied('C5 teacher cannot change a status', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$update public.posts set status = 'published' where id = (select pg_temp.note_id('Mrs. Santos'))$q$);

select pg_temp.expect_rows('C6 teacher can revise their own pending note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$update public.posts set content = 'You made my first semester here feel a lot less scary. Thank you.'
     where id = (select pg_temp.note_id('Ms. Reyes'))$q$,
  1);

select pg_temp.expect_rows('C7 teacher cannot edit another teacher''s note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$update public.posts set content = 'tampered' where id = (select pg_temp.note_id('All Teachers'))$q$,
  0);

select pg_temp.check(
  'C8 the other teacher''s note is untouched',
  (select content = 'Some days we teach. Some days we survive. Both count.'
     from public.posts where id = (select pg_temp.note_id('All Teachers'))),
  ''
);

select pg_temp.expect_denied('C9 teacher cannot delete any note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  'delete from public.posts');

select pg_temp.expect_count('C10 teacher reads only their own notes', 'authenticated',
  '11111111-1111-4111-8111-111111111111', 'select * from public.posts', 4);

select pg_temp.expect_count('C11 the other teacher reads only their own notes', 'authenticated',
  '22222222-2222-4222-8222-222222222222', 'select * from public.posts', 1);

select pg_temp.expect_denied('C12 teacher cannot change their own role', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$update public.profiles set role = 'admin' where id = '11111111-1111-4111-8111-111111111111'$q$);

select pg_temp.expect_ok('C13 teacher can rename their own profile', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$update public.profiles set display_name = 'Ms. A. Rivera'
     where id = '11111111-1111-4111-8111-111111111111'$q$);

select pg_temp.expect_count('C14 teacher sees only their own profile', 'authenticated',
  '11111111-1111-4111-8111-111111111111', 'select * from public.profiles', 1);

select pg_temp.expect_denied('C15 teacher cannot approve a note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.admin_moderate_post((select pg_temp.note_id('All Teachers')), 'approve')$q$);

select pg_temp.expect_denied('C16 teacher cannot reject a note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.admin_moderate_post((select pg_temp.note_id('All Teachers')), 'reject', 'because', 'Other')$q$);

select pg_temp.expect_denied('C17 teacher cannot remove a note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.admin_moderate_post((select pg_temp.note_id('Mrs. Thornbull')), 'remove')$q$);

select pg_temp.expect_count('C18 teacher cannot read reports', 'authenticated',
  '11111111-1111-4111-8111-111111111111', 'select * from public.reports', 0);

select pg_temp.expect_count('C19 teacher cannot read moderation logs', 'authenticated',
  '11111111-1111-4111-8111-111111111111', 'select * from public.moderation_logs', 0);

select pg_temp.expect_denied('C20 teacher cannot read dashboard stats', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  'select public.admin_dashboard_stats()');

select pg_temp.expect_denied('C21 teacher cannot promote anyone', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.admin_set_user_role('22222222-2222-4222-8222-222222222222', 'admin')$q$);

select pg_temp.expect_denied('C22 teacher cannot insert reports directly', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$insert into public.reports (post_id, reporter_id, reason)
    values ((select pg_temp.note_id('Mrs. Thornbull')), '11111111-1111-4111-8111-111111111111', 'Spam')$q$);

select pg_temp.expect_denied('C23 teacher cannot forge a moderation log', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$insert into public.moderation_logs (post_id, moderator_id, moderator_display_name,
       post_recipient, action)
    values (gen_random_uuid(), '11111111-1111-4111-8111-111111111111', 'Fake', 'X', 'approve')$q$);

select pg_temp.expect_denied('C24 moderation logs cannot be edited', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  'update public.moderation_logs set reason = ''tampered''');

select pg_temp.expect_denied('C25 moderation logs cannot be deleted', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  'delete from public.moderation_logs');

select pg_temp.expect_ok('C26 teacher can file a report', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.submit_report((select pg_temp.note_id('Mrs. Thornbull')), 'Offensive content', 'test report')$q$);

select pg_temp.expect_denied('C27 duplicate open report is refused', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.submit_report((select pg_temp.note_id('Mrs. Thornbull')), 'Spam', null)$q$);

select pg_temp.expect_denied('C28 cannot report a note that is not published', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.submit_report((select pg_temp.note_id('All Teachers')), 'Spam', null)$q$);

select pg_temp.expect_denied('C29 teacher cannot resubmit someone else''s note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.resubmit_post((select pg_temp.note_id('All Teachers')))$q$);

-- ---------------------------------------------------------------------------
-- D. Admin / moderator
-- ---------------------------------------------------------------------------

select pg_temp.expect_ok('D1 admin can read every note', 'authenticated',
  '33333333-3333-4333-8333-333333333333', 'select * from public.posts');

select pg_temp.expect_ok('D2 admin can read reports', 'authenticated',
  '33333333-3333-4333-8333-333333333333', 'select * from public.reports');

select pg_temp.expect_ok('D3 admin can read moderation logs', 'authenticated',
  '33333333-3333-4333-8333-333333333333', 'select * from public.moderation_logs');

select pg_temp.expect_ok('D4 admin can read dashboard stats', 'authenticated',
  '33333333-3333-4333-8333-333333333333', 'select public.admin_dashboard_stats()');

select pg_temp.expect_ok('D5 admin approves a pending note', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  $q$select public.admin_moderate_post((select pg_temp.note_id('All Teachers')), 'approve')$q$);

select pg_temp.check(
  'D6 approval stamps reviewer and timestamp',
  exists (
    select 1 from public.posts
     where id = (select pg_temp.note_id('All Teachers'))
       and status = 'published'
       and reviewed_at is not null
       and reviewed_by = '33333333-3333-4333-8333-333333333333'
  ),
  ''
);

select pg_temp.check(
  'D7 approval writes a moderation log',
  exists (
    select 1 from public.moderation_logs
     where post_id = (select pg_temp.note_id('All Teachers'))
       and action = 'approve'
       and previous_status = 'pending'
       and new_status = 'published'
       and moderator_id = '33333333-3333-4333-8333-333333333333'
       and post_recipient = 'All Teachers'
  ),
  ''
);

select pg_temp.expect_ok('D8 rejection stores a private reason', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  $q$select public.admin_moderate_post((select pg_temp.note_id('Sir Daniel')), 'reject',
       'Contains a private phone number', 'Personal information')$q$);

select pg_temp.check(
  'D9 rejection reason is stored but never public',
  exists (
    select 1 from public.posts
     where id = (select pg_temp.note_id('Sir Daniel'))
       and status = 'rejected'
       and rejection_reason = 'Personal information'
  )
  and exists (select 1 from public.moderation_logs where post_id = (select pg_temp.note_id('Sir Daniel')) and action = 'reject')
  and not exists (select 1 from public.posts_public
                   where id = (select id from public.posts where recipient = 'Sir Daniel')),
  ''
);

select pg_temp.expect_ok('D10 the author can resubmit their rejected note', 'authenticated',
  '11111111-1111-4111-8111-111111111111',
  $q$select public.resubmit_post((select pg_temp.note_id('Sir Daniel')))$q$);

select pg_temp.check(
  'D11 resubmission clears the rejection state',
  exists (
    select 1 from public.posts
     where id = (select pg_temp.note_id('Sir Daniel'))
       and status = 'pending'
       and rejection_reason is null
       and reviewed_at is null
  ),
  ''
);

select pg_temp.expect_ok('D12 admin removes a published note', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  $q$select public.admin_moderate_post((select pg_temp.note_id('Mrs. Thornbull')), 'remove', 'Reported by staff')$q$);

select pg_temp.check(
  'D13 removed notes vanish from the public wall but are not deleted',
  not exists (select 1 from public.posts_public where id = (select pg_temp.note_id('Mrs. Thornbull')))
  and exists (
    select 1 from public.posts where id = (select pg_temp.note_id('Mrs. Thornbull')) and status = 'removed'
  ),
  ''
);

select pg_temp.expect_ok('D14 admin restores a removed note', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  $q$select public.admin_moderate_post((select pg_temp.note_id('Mrs. Thornbull')), 'restore')$q$);

select pg_temp.expect_denied('D15 invalid transition is refused', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  $q$select public.admin_moderate_post((select pg_temp.note_id('Mrs. Thornbull')), 'approve')$q$);

select pg_temp.expect_ok('D16 admin dismisses a report', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  $q$select public.admin_handle_report(
       (select id from public.reports where status = 'pending' limit 1),
       'dismiss', 'Reviewed, note is fine')$q$);

select pg_temp.check(
  'D17 report resolution is recorded in the log',
  exists (
    select 1 from public.moderation_logs
     where action = 'dismiss_report' and reason = 'Reviewed, note is fine'
  ),
  ''
);

-- A second report, resolved by taking the note down.
do $$
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  perform public.submit_report(
    (select id from public.posts where recipient = 'All Teachers'),
    'Personal information', 'second report'
  );
end;
$$;

select pg_temp.expect_ok('D18 admin removes a note through a report', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  $q$select public.admin_handle_report(
       (select id from public.reports where details = 'second report'),
       'remove_post', 'Confirmed spam')$q$);

select pg_temp.check(
  'D19 report removal updates both the report and the note',
  exists (
    select 1 from public.reports
     where details = 'second report' and status = 'action_taken'
  )
  and exists (
    select 1 from public.posts where id = (select pg_temp.note_id('All Teachers')) and status = 'removed'
  )
  and exists (
    select 1 from public.moderation_logs
     where post_recipient = 'All Teachers' and action = 'remove'
  ),
  ''
);

select pg_temp.expect_ok('D20 admin can keep a reported note published', 'authenticated',
  '33333333-3333-4333-8333-333333333333',
  $q$select public.admin_handle_report(
       (select id from public.reports where status = 'pending' limit 1),
       'keep_published', 'Looks fine')$q$);

do $$
declare v_stats jsonb;
begin
  perform set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
  v_stats := public.admin_dashboard_stats();

  perform pg_temp.check(
    'D21 dashboard statistics match reality',
    (v_stats ->> 'pending_count')::int
        = (select count(*) from public.posts where status = 'pending')
    and (v_stats ->> 'published_count')::int
        = (select count(*) from public.posts where status = 'published')
    and (v_stats ->> 'rejected_count')::int
        = (select count(*) from public.posts where status = 'rejected')
    and (v_stats ->> 'removed_count')::int
        = (select count(*) from public.posts where status = 'removed')
    and (v_stats ->> 'report_total')::int
        = (select count(*) from public.reports)
    and (v_stats ->> 'admin_count')::int = 1
    and (v_stats ->> 'teacher_count')::int = 2,
    v_stats::text
  );
end;
$$;

select pg_temp.expect_denied('D22 first-admin bootstrap refuses once an admin exists',
  'service_role', null,
  $q$select public.bootstrap_first_admin('teacher.a@example.test')$q$);

select pg_temp.expect_denied('D23 a guest cannot reach moderation functions', 'anon', null,
  $q$select public.admin_moderate_post((select pg_temp.note_id('Mrs. Thornbull')), 'approve')$q$);

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------

select case when ok then 'PASS' else 'FAIL' end as result, label, detail
  from sec_results
 order by seq;

select count(*) filter (where ok)    as passed,
       count(*) filter (where not ok) as failed
  from sec_results;