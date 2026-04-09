-- App Store 3.1.1: remove non-IAP subscription unlock (redeem_complimentary_access_code / MIYAFRIEND).
-- Keep families.complimentary_access column for historical rows; app no longer reads it for paywall.

drop function if exists public.redeem_complimentary_access_code(text);

-- Restore billing RPC shape without complimentary_access (paywall uses StoreKit only).
create or replace function public.get_my_family_billing_state()
returns table (
  family_id uuid,
  billing_status text,
  billing_owner_user_id uuid,
  billing_grace_until timestamptz,
  role text
)
language sql
security definer
set search_path = public
as $$
  select
    f.id as family_id,
    f.billing_status,
    f.billing_owner_user_id,
    f.billing_grace_until,
    fm.role
  from public.family_members fm
  join public.families f
    on f.id = fm.family_id
  where fm.user_id = auth.uid()
    and fm.invite_status = 'accepted'
  limit 1
$$;

comment on function public.get_my_family_billing_state is
  'Returns family billing status for the authenticated member.';
