-- =====================================================
-- Bell notifications RPC: scoped view over notification_queue
-- Surfaces only personal + challenge-related notifications
-- for the current authenticated user (recipient_user_id = auth.uid()).
-- =====================================================

create or replace function public.get_bell_notifications(
  p_limit integer default 25
)
returns table (
  id uuid,
  created_at timestamptz,
  recipient_user_id uuid,
  member_user_id uuid,
  alert_state_id uuid,
  payload jsonb
)
language sql
security definer
set search_path = public
as $$
  select
    q.id,
    q.created_at,
    q.recipient_user_id,
    q.member_user_id,
    q.alert_state_id,
    q.payload
  from public.notification_queue q
  where q.recipient_user_id = auth.uid()
    and q.channel = 'push'
    and q.status in ('pending', 'sent')
    and (q.payload->>'kind') in (
      'personal_trend',
      'pattern_alert',
      'challenge_invite',
      'challenge_daily_member',
      'challenge_daily_admin',
      'challenge_completed_member',
      'challenge_completed_admin'
    )
  order by q.created_at desc
  limit coalesce(p_limit, 25);
$$;

comment on function public.get_bell_notifications is
  'Return personal, pattern trigger, and challenge bell notifications for the current user from notification_queue.';

