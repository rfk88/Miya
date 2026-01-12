-- =====================================================
-- RPC: update_my_member_first_name
-- This provides a safe, RLS-resistant way for a signed-in user to update their
-- own `family_members.first_name` (and keep `user_profiles.first_name` in sync),
-- even in projects where RLS is enabled on `family_members` without an update policy.
-- =====================================================

create or replace function public.update_my_member_first_name(new_first_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_name text;
begin
  trimmed_name := nullif(btrim(new_first_name), '');
  if trimmed_name is null then
    raise exception 'first_name cannot be empty';
  end if;

  -- Update family_members for the current auth user (if present).
  update public.family_members
     set first_name = trimmed_name
   where user_id = auth.uid();

  -- Keep user_profiles in sync (canonical name lives here).
  update public.user_profiles
     set first_name = trimmed_name
   where user_id = auth.uid();
end;
$$;

revoke all on function public.update_my_member_first_name(text) from public;
grant execute on function public.update_my_member_first_name(text) to authenticated;

