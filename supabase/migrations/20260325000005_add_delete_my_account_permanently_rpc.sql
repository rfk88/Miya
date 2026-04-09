-- Permanent account deletion helper RPC.
-- NOTE: This function handles app-domain cleanup (family membership + billing transition).
-- Auth user deletion is performed by a service-role Edge Function after this RPC succeeds.

create or replace function public.delete_my_account_permanently()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  begin
    result := public.delete_my_account_with_family_billing();
  exception
    when others then
      return jsonb_build_object(
        'success', false,
        'stage', 'family_cleanup_failed',
        'message', sqlerrm,
        'requires_admin_cleanup', false
      );
  end;

  return jsonb_build_object(
    'success', true,
    'stage', case
      when coalesce((result ->> 'family_changed')::boolean, false) then 'family_cleanup_complete'
      else 'already_not_in_family_or_member_cleanup_complete'
    end,
    'message', 'App-domain cleanup complete',
    'requires_admin_cleanup', false,
    'family_result', result
  );
end;
$$;

comment on function public.delete_my_account_permanently is
  'Performs app-domain account cleanup for the authenticated user. Auth user deletion must be done by privileged service role after this RPC succeeds.';
