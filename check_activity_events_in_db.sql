-- Check if we've received activity_event webhooks in production
SELECT 
  COUNT(*) as activity_event_webhooks,
  MIN(created_at) as first_received,
  MAX(created_at) as last_received
FROM rook_webhook_events
WHERE payload->>'data_structure' = 'activity_event';

-- Show a sample
SELECT 
  created_at,
  payload#>>'{physical_health,events,activity_event,0,activity,activity_type_name_string}' as activity_type,
  payload#>>'{physical_health,events,activity_event,0,activity,activity_duration_seconds_int}' as duration_seconds
FROM rook_webhook_events
WHERE payload->>'data_structure' = 'activity_event'
ORDER BY created_at DESC
LIMIT 5;
