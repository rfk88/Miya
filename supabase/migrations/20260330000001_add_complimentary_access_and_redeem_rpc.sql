-- Complimentary access (e.g. MIYAFRIEND promo) for family creators; paywall gate reads via get_my_family_billing_state.

alter table if exists public.families
  add column if not exists complimentary_access boolean not null default false;

comment on column public.families.complimentary_access is
  'When true, app may treat the family as having access without StoreKit subscription (server-validated promo).';

-- Redeem canonical code; only the family creator (families.created_by) may apply it to their family.
create or replace function public.redeem_complimentary_access_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  fam_id uuid;
begin
  if caller_id is null then
    return jsonb_build_object('success', false, 'error', 'not_authenticated');
  end if;

  if lower(trim(coalesce(p_code, ''))) <> 'miyafriend' then
    return jsonb_build_object('success', false, 'error', 'invalid_code');
  end if;

  select f.id
  into fam_id
  from public.families f
  inner join public.family_members fm
    on fm.family_id = f.id
   and fm.user_id = caller_id
   and fm.invite_status = 'accepted'
  where f.created_by = caller_id
  limit 1;

  if fam_id is null then
    return jsonb_build_object('success', false, 'error', 'no_family_or_not_creator');
  end if;

  update public.families
  set complimentary_access = true
  where id = fam_id
    and not complimentary_access;

  return jsonb_build_object('success', true, 'family_id', fam_id::text);
end;
$$;

comment on function public.redeem_complimentary_access_code is
  'Validates promo code and sets families.complimentary_access for the caller''s created family. Idempotent if already set.';

grant execute on function public.redeem_complimentary_access_code(text) to authenticated;

-- Include complimentary_access in billing state for paywall / client.
create or replace function public.get_my_family_billing_state()
returns table (
  family_id uuid,
  billing_status text,
  billing_owner_user_id uuid,
  billing_grace_until timestamptz,
  role text,
  complimentary_access boolean
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
    fm.role,
    f.complimentary_access
  from public.family_members fm
  join public.families f
    on f.id = fm.family_id
  where fm.user_id = auth.uid()
    and fm.invite_status = 'accepted'
  limit 1
$$;

comment on function public.get_my_family_billing_state is
  'Returns family billing status and complimentary_access for the authenticated member.';
