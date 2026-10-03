-- Explicit RPC grants for a database that was provisioned before migration history.
-- Admin-only entry points must never be callable by the anonymous PostgREST role.
revoke all on function public.admin_moderate_post(uuid, public.moderation_action, text, public.rejection_reason) from anon;
revoke all on function public.admin_handle_report(uuid, text, text) from anon;
revoke all on function public.admin_dashboard_stats() from anon;
revoke all on function public.admin_set_user_role(uuid, public.user_role) from anon;
revoke all on function public.resubmit_post(uuid) from anon;
revoke all on function public.bootstrap_first_admin(text) from anon, authenticated;
revoke all on function public.is_admin() from anon;
revoke all on function public.current_user_role() from anon;

grant execute on function public.admin_moderate_post(uuid, public.moderation_action, text, public.rejection_reason) to authenticated;
grant execute on function public.admin_handle_report(uuid, text, text) to authenticated;
grant execute on function public.admin_dashboard_stats() to authenticated;
grant execute on function public.admin_set_user_role(uuid, public.user_role) to authenticated;
grant execute on function public.resubmit_post(uuid) to authenticated;
grant execute on function public.bootstrap_first_admin(text) to service_role;
grant execute on function public.is_admin() to authenticated, service_role;
grant execute on function public.current_user_role() to authenticated, service_role;
grant execute on function public.submit_report(uuid, public.report_reason, text) to anon, authenticated;