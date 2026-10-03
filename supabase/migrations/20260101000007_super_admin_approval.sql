-- Super-admin approval flow for new registrations.
alter type public.user_role add value if not exists 'super_admin';

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin', 'super_admin'));
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'super_admin');
$$;
revoke all on function public.is_super_admin() from public, anon;
grant execute on function public.is_super_admin() to authenticated, service_role;

create table if not exists public.admin_access_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null
);
alter table public.admin_access_requests enable row level security;
revoke all on table public.admin_access_requests from anon, authenticated;
grant select on table public.admin_access_requests to authenticated;
drop policy if exists admin_access_requests_select_super_admin on public.admin_access_requests;
create policy admin_access_requests_select_super_admin on public.admin_access_requests for select to authenticated using ((select public.is_super_admin()));

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_requested_name text; v_display_name text;
begin
  v_requested_name := coalesce(new.raw_user_meta_data ->> 'display_name', '');
  if char_length(btrim(v_requested_name)) between 1 and 60 then v_display_name := btrim(v_requested_name);
  else v_display_name := left(coalesce(nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'New Teacher'), 60); end if;
  insert into public.profiles (id, role, display_name) values (new.id, 'teacher', v_display_name) on conflict (id) do nothing;
  insert into public.admin_access_requests (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;

create or replace function public.review_admin_access_request(p_request_id uuid, p_approve boolean)
returns public.admin_access_requests language plpgsql security definer set search_path = '' as $$
declare v_request public.admin_access_requests;
begin
  if not (select public.is_super_admin()) then raise exception 'Super-admin access is required.' using errcode = '42501'; end if;
  select * into v_request from public.admin_access_requests where id = p_request_id for update;
  if not found then raise exception 'That access request no longer exists.' using errcode = 'P0002'; end if;
  if v_request.status <> 'pending' then raise exception 'That access request has already been reviewed.' using errcode = '22023'; end if;
  update public.admin_access_requests set status = case when p_approve then 'approved' else 'rejected' end, reviewed_at = now(), reviewed_by = auth.uid() where id = v_request.id returning * into v_request;
  if p_approve then update public.profiles set role = 'admin' where id = v_request.user_id; end if;
  return v_request;
end;
$$;
revoke all on function public.review_admin_access_request(uuid, boolean) from public, anon;
grant execute on function public.review_admin_access_request(uuid, boolean) to authenticated;

create or replace function public.admin_promote_user_by_email(p_email text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid; v_profile public.profiles;
begin
  if not (select public.is_super_admin()) then raise exception 'Super-admin access is required.' using errcode = '42501'; end if;
  select id into v_user_id from auth.users where lower(email) = lower(btrim(coalesce(p_email, '')));
  if v_user_id is null then raise exception 'No registered account matches that email address.' using errcode = 'P0002'; end if;
  update public.profiles set role = 'admin' where id = v_user_id returning * into v_profile;
  return v_profile;
end;
$$;