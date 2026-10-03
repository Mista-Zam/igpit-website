create or replace function public.admin_delete_post(p_post_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_moderator uuid := (select auth.uid()); v_name text; v_post public.posts; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not (select public.is_admin()) then raise exception 'Administrator access is required to delete notes.' using errcode = '42501'; end if;
  if char_length(coalesce(v_reason, '')) > 500 then raise exception 'Deletion notes must be under 500 characters.' using errcode = '22023'; end if;
  select * into v_post from public.posts where id = p_post_id for update;
  if not found then raise exception 'That note no longer exists.' using errcode = 'P0002'; end if;
  select display_name into v_name from public.profiles where id = v_moderator;
  insert into public.moderation_logs (post_id, moderator_id, moderator_display_name, post_recipient, action, reason, previous_status, new_status) values (v_post.id, v_moderator, coalesce(v_name, 'Moderator'), v_post.recipient, 'remove', coalesce(v_reason, 'Permanently deleted by administrator'), v_post.status, null);
  delete from public.posts where id = v_post.id;
end; $$;
revoke all on function public.admin_delete_post(uuid, text) from public, anon;
grant execute on function public.admin_delete_post(uuid, text) to authenticated;