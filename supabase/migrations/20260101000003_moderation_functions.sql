-- ===========================================================================
-- Teachers' Freedom Wall
-- 003_moderation_functions.sql
--
-- SECURITY DEFINER entry points. Every status change in the system happens
-- inside one of these functions, which:
--   1. re-checks `public.is_admin()` (or ownership) server-side,
--   2. performs the state transition atomically,
--   3. writes the matching `moderation_logs` row in the same transaction.
--
-- Because reports and moderation_logs have no INSERT/UPDATE/DELETE grants for
-- `authenticated`, these functions are the only way to write to them.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- submit_report — public: file a report against a published note
-- ---------------------------------------------------------------------------

create or replace function public.submit_report(
  p_post_id uuid,
  p_reason  public.report_reason,
  p_details text default null
)
returns public.reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reporter uuid := (select auth.uid());
  v_details  text;
  v_post     public.posts;
  v_report   public.reports;
begin
  if p_reason is null then
    raise exception 'Please choose a reason for your report.'
      using errcode = '22023';
  end if;

  v_details := nullif(btrim(coalesce(p_details, '')), '');
  if v_details is not null and char_length(v_details) > 1000 then
    raise exception 'Please keep report details under 1000 characters.'
      using errcode = '22023';
  end if;

  -- Only published notes can be reported.
  select * into v_post
    from public.posts
   where id = p_post_id
     and status = 'published';

  if not found then
    raise exception 'That note is not available for reporting.'
      using errcode = 'P0002';
  end if;

  -- One open report per signed-in reporter.
  if v_reporter is not null and exists (
    select 1 from public.reports
     where post_id = p_post_id
       and reporter_id = v_reporter
       and status = 'pending'
  ) then
    raise exception 'You have already reported this note. Our moderators will take a look.'
      using errcode = '23505';
  end if;

  insert into public.reports (post_id, reporter_id, reason, details)
  values (p_post_id, v_reporter, p_reason, v_details)
  returning * into v_report;

  return v_report;
end;
$$;

revoke all on function public.submit_report(uuid, public.report_reason, text) from public;
grant execute on function public.submit_report(uuid, public.report_reason, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- resubmit_post — author revives a rejected note for another review pass
-- ---------------------------------------------------------------------------

create or replace function public.resubmit_post(p_post_id uuid)
returns public.posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_post  public.posts;
  v_owner uuid;
begin
  select author_id into v_owner from public.posts where id = p_post_id;
  if not found then
    raise exception 'That note no longer exists.' using errcode = 'P0002';
  end if;

  if v_owner is distinct from v_uid then
    raise exception 'You can only resubmit your own notes.' using errcode = '42501';
  end if;

  update public.posts
     set status           = 'pending',
         reviewed_at      = null,
         reviewed_by      = null,
         rejection_reason = null
   where id = p_post_id
     and status = 'rejected'
  returning * into v_post;

  if not found then
    raise exception 'Only rejected notes can be resubmitted.' using errcode = '22023';
  end if;

  return v_post;
end;
$$;

revoke all on function public.resubmit_post(uuid) from public;
grant execute on function public.resubmit_post(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_moderate_post — approve / reject / remove / restore
--
-- Called as: rpc('admin_moderate_post', {
--   p_post_id, p_action, p_reason, p_rejection_reason
-- })
-- ---------------------------------------------------------------------------

create or replace function public.admin_moderate_post(
  p_post_id           uuid,
  p_action            public.moderation_action,
  p_reason            text default null,
  p_rejection_reason  public.rejection_reason default null
)
returns public.posts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_moderator uuid := (select auth.uid());
  v_name      text;
  v_before    public.post_status;
  v_after     public.post_status;
  v_reason    text;
  v_reject    public.rejection_reason;
  v_post      public.posts;
begin
  if not (select public.is_admin()) then
    raise exception 'Administrator access is required to moderate notes.'
      using errcode = '42501';
  end if;

  if p_action not in ('approve', 'reject', 'remove', 'restore') then
    raise exception 'Unsupported moderation action.'
      using errcode = '22023';
  end if;

  select * into v_post from public.posts where id = p_post_id for update;
  if not found then
    raise exception 'That note no longer exists.' using errcode = 'P0002';
  end if;

  select display_name into v_name from public.profiles where id = v_moderator;
  v_before := v_post.status;

  case p_action
    when 'approve' then
      if v_before not in ('pending', 'rejected') then
        raise exception 'Only pending or rejected notes can be approved.'
          using errcode = '22023';
      end if;
      v_after  := 'published';
      v_reason := null;
      v_reject := null;

    when 'reject' then
      if v_before not in ('pending', 'published') then
        raise exception 'Only pending or published notes can be rejected.'
          using errcode = '22023';
      end if;
      v_reject := coalesce(p_rejection_reason, 'Other'::public.rejection_reason);
      v_reason := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), v_reject::text);
      v_after  := 'rejected';

    when 'remove' then
      if v_before = 'removed' then
        raise exception 'That note has already been removed.' using errcode = '22023';
      end if;
      v_after  := 'removed';
      v_reason := nullif(btrim(coalesce(p_reason, '')), '');
      v_reject := v_post.rejection_reason;

    when 'restore' then
      if v_before <> 'removed' then
        raise exception 'Only removed notes can be restored.' using errcode = '22023';
      end if;
      v_after  := 'published';
      v_reason := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Restored by moderator');
      v_reject := null;
  end case;

  if char_length(coalesce(v_reason, '')) > 500 then
    raise exception 'Moderation notes must be under 500 characters.' using errcode = '22023';
  end if;

  update public.posts
     set status           = v_after,
         reviewed_at      = now(),
         reviewed_by      = v_moderator,
         rejection_reason = v_reject
   where id = p_post_id
  returning * into v_post;

  insert into public.moderation_logs (
    post_id, moderator_id, moderator_display_name, post_recipient,
    action, reason, previous_status, new_status
  )
  values (
    p_post_id, v_moderator, coalesce(v_name, 'Moderator'), v_post.recipient,
    p_action, v_reason, v_before, v_after
  );

  return v_post;
end;
$$;

revoke all on function public.admin_moderate_post(uuid, public.moderation_action, text, public.rejection_reason) from public;
grant execute on function public.admin_moderate_post(uuid, public.moderation_action, text, public.rejection_reason) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_handle_report — dismiss / keep published / remove the note
--
-- Called as: rpc('admin_handle_report', { p_report_id, p_decision, p_reason })
--   p_decision: 'dismiss' | 'keep_published' | 'remove_post'
-- ---------------------------------------------------------------------------

create or replace function public.admin_handle_report(
  p_report_id uuid,
  p_decision  text,
  p_reason    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_moderator uuid := (select auth.uid());
  v_name      text;
  v_reason    text;
  v_report    public.reports;
  v_post      public.posts;
  v_before    public.post_status;
begin
  if not (select public.is_admin()) then
    raise exception 'Administrator access is required to resolve reports.'
      using errcode = '42501';
  end if;

  if p_decision not in ('dismiss', 'keep_published', 'remove_post') then
    raise exception 'Unsupported report decision.' using errcode = '22023';
  end if;

  select * into v_report from public.reports where id = p_report_id for update;
  if not found then
    raise exception 'That report no longer exists.' using errcode = 'P0002';
  end if;

  if v_report.status <> 'pending' then
    raise exception 'That report has already been resolved.' using errcode = '22023';
  end if;

  select display_name into v_name from public.profiles where id = v_moderator;
  v_reason := nullif(btrim(coalesce(p_reason, '')), '');

  -- Optionally take the note down as part of resolving the report.
  if p_decision = 'remove_post' then
    select * into v_post from public.posts where id = v_report.post_id for update;
    if found and v_post.status <> 'removed' then
      v_before := v_post.status;

      update public.posts
         set status      = 'removed',
             reviewed_at = now(),
             reviewed_by = v_moderator
       where id = v_report.post_id;

      insert into public.moderation_logs (
        post_id, moderator_id, moderator_display_name, post_recipient,
        action, reason, previous_status, new_status
      )
      values (
        v_report.post_id, v_moderator, coalesce(v_name, 'Moderator'), v_post.recipient,
        'remove', coalesce(v_reason, 'Removed while resolving a report'), v_before, 'removed'
      );
    end if;
  end if;

  update public.reports
     set status      = (case p_decision
                          when 'dismiss'        then 'dismissed'::public.report_status
                          when 'keep_published' then 'reviewed'::public.report_status
                          else 'action_taken'::public.report_status
                        end),
         resolved_at = now(),
         resolved_by = v_moderator
   where id = p_report_id;

  insert into public.moderation_logs (
    post_id, moderator_id, moderator_display_name, post_recipient,
    action, reason, previous_status, new_status
  )
  values (
    v_report.post_id, v_moderator, coalesce(v_name, 'Moderator'),
    coalesce(v_post.recipient, '—'),
    case p_decision
      when 'dismiss' then 'dismiss_report'::public.moderation_action
      else 'resolve_report'::public.moderation_action
    end,
    v_reason,
    null,
    null
  );

  return jsonb_build_object(
    'report_id', p_report_id,
    'decision',  p_decision,
    'status',    case p_decision
                    when 'dismiss'        then 'dismissed'
                    when 'keep_published' then 'reviewed'
                    else 'action_taken'
                  end
  );
end;
$$;

revoke all on function public.admin_handle_report(uuid, text, text) from public;
grant execute on function public.admin_handle_report(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- admin_dashboard_stats — real counts, never hardcoded
-- ---------------------------------------------------------------------------

create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
begin
  if not (select public.is_admin()) then
    raise exception 'Administrator access is required.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'pending_count',    (select count(*) from public.posts where status = 'pending'),
    'published_count',  (select count(*) from public.posts where status = 'published'),
    'rejected_count',   (select count(*) from public.posts where status = 'rejected'),
    'removed_count',    (select count(*) from public.posts where status = 'removed'),
    'total_count',      (select count(*) from public.posts),
    'report_count',     (select count(*) from public.reports where status = 'pending'),
    'report_total',     (select count(*) from public.reports),
    'teacher_count',    (select count(*) from public.profiles where role = 'teacher'),
    'admin_count',      (select count(*) from public.profiles where role = 'admin'),
    'today_count',      (
      select count(*) from public.posts
       where created_at >= (v_today::timestamp at time zone 'utc')
    ),
    'today_reports',    (
      select count(*) from public.reports
       where created_at >= (v_today::timestamp at time zone 'utc')
    ),
    'moderation_count', (select count(*) from public.moderation_logs),
    'v_today',          v_today
  );
end;
$$;

revoke all on function public.admin_dashboard_stats() from public;
grant execute on function public.admin_dashboard_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- admin_set_user_role — promote/demote a teacher (admins only)
-- ---------------------------------------------------------------------------

create or replace function public.admin_set_user_role(
  p_target_id uuid,
  p_role      public.user_role
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  if not (select public.is_admin()) then
    raise exception 'Administrator access is required.' using errcode = '42501';
  end if;

  if p_role is null then
    raise exception 'A role is required.' using errcode = '22023';
  end if;

  update public.profiles
     set role = p_role
   where id = p_target_id
  returning * into v_profile;

  if not found then
    raise exception 'That profile no longer exists.' using errcode = 'P0002';
  end if;

  return v_profile;
end;
$$;

revoke all on function public.admin_set_user_role(uuid, public.user_role) from public;
grant execute on function public.admin_set_user_role(uuid, public.user_role) to authenticated;

-- ---------------------------------------------------------------------------
-- bootstrap_first_admin — create the very first administrator
--
-- Refuses to run once any admin exists, so it cannot be used to escalate.
-- Intended to be called from the Supabase SQL editor after registering the
-- teacher account through the normal sign-up form.
-- ---------------------------------------------------------------------------

create or replace function public.bootstrap_first_admin(p_email text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_name    text;
  v_profile public.profiles;
begin
  if not (select public.is_privileged_writer()) then
    raise exception 'This function may only be run from the SQL editor or a service-role backend.'
      using errcode = '42501';
  end if;

  if exists (select 1 from public.profiles where role = 'admin') then
    raise exception 'An administrator already exists. Use admin_set_user_role() instead.'
      using errcode = '42501';
  end if;

  select id, coalesce(raw_user_meta_data ->> 'display_name', '')
    into v_user_id, v_name
    from auth.users
   where lower(email) = lower(btrim(coalesce(p_email, '')));

  if v_user_id is null then
    raise exception 'No registered account matches that email address.' using errcode = 'P0002';
  end if;

  update public.profiles
     set role = 'admin'
   where id = v_user_id
  returning * into v_profile;

  return v_profile;
end;
$$;

revoke all on function public.bootstrap_first_admin(text) from public;
grant execute on function public.bootstrap_first_admin(text) to service_role;