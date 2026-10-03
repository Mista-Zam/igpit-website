-- Lets an existing administrator promote a registered account by email.
create or replace function public.admin_promote_user_by_email(p_email text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare v_user_id uuid; v_profile public.profiles;
begin
  if not (select public.is_admin()) then raise exception 'Administrator access is required.' using errcode = '42501'; end if;
  select id into v_user_id from auth.users where lower(email) = lower(btrim(coalesce(p_email, '')));
  if v_user_id is null then raise exception 'No registered account matches that email address.' using errcode = 'P0002'; end if;
  update public.profiles set role = 'admin' where id = v_user_id returning * into v_profile;
  return v_profile;
end;
$$;
revoke all on function public.admin_promote_user_by_email(text) from public, anon;
grant execute on function public.admin_promote_user_by_email(text) to authenticated;