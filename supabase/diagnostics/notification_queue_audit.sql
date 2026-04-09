-- Notification queue audit (run in SQL editor). Correlates kinds vs push/bell behavior.

-- Count by kind and status
select
  payload->>'kind' as kind,
  status,
  count(*) as n
from public.notification_queue
where created_at > now() - interval '30 days'
group by 1, 2
order by n desc;

-- Recent rows where push may have been marked sent without APNs body (legacy); after worker fix, expect none.
select id, created_at, status, last_error, payload->>'kind' as kind
from public.notification_queue
where status = 'sent'
  and created_at > now() - interval '7 days'
order by created_at desc
limit 100;
