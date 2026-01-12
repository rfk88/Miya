-- Quick check: How many activity_event webhooks are available for backfill?
-- Run this BEFORE the backfill to see what data is available

SELECT 
  'Activity Events Available for Backfill' as check_type,
  COUNT(*) as total_activity_webhooks,
  COUNT(DISTINCT payload->>'user_id') as unique_users,
  MIN(created_at) as earliest_event,
  MAX(created_at) as latest_event,
  COUNT(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN 1 END) as last_7_days,
  COUNT(CASE WHEN created_at >= NOW() - INTERVAL '30 days' THEN 1 END) as last_30_days,
  COUNT(CASE WHEN created_at >= NOW() - INTERVAL '90 days' THEN 1 END) as last_90_days
FROM rook_webhook_events
WHERE payload->>'data_structure' = 'activity_event' 
   OR payload->>'dataStructure' = 'activity_event';

-- Show sample user IDs that have activity events
SELECT DISTINCT
  COALESCE(
    payload->>'user_id',
    payload->>'userId',
    payload#>>'{physical_health,events,activity_event,0,metadata,user_id_string}'
  ) as rook_user_id,
  COUNT(*) as activity_event_count,
  MIN(created_at) as first_event,
  MAX(created_at) as last_event
FROM rook_webhook_events
WHERE payload->>'data_structure' = 'activity_event' 
   OR payload->>'dataStructure' = 'activity_event'
GROUP BY rook_user_id
ORDER BY activity_event_count DESC
LIMIT 10;

-- Check if these users are mapped
WITH activity_users AS (
  SELECT DISTINCT
    COALESCE(
      payload->>'user_id',
      payload->>'userId',
      payload#>>'{physical_health,events,activity_event,0,metadata,user_id_string}'
    ) as rook_user_id
  FROM rook_webhook_events
  WHERE payload->>'data_structure' = 'activity_event' 
     OR payload->>'dataStructure' = 'activity_event'
)
SELECT 
  au.rook_user_id,
  rum.user_id as mapped_to_miya_user_id,
  CASE 
    WHEN au.rook_user_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' 
      THEN 'Direct UUID'
    WHEN rum.user_id IS NOT NULL 
      THEN 'Mapped'
    ELSE 'NOT MAPPED - Need to add mapping'
  END as mapping_status
FROM activity_users au
LEFT JOIN rook_user_mapping rum ON rum.rook_user_id = au.rook_user_id
ORDER BY mapping_status, au.rook_user_id;

-- Sample of activity types available
SELECT 
  payload#>>'{physical_health,events,activity_event,0,activity,activity_type_name_string}' as activity_type,
  COUNT(*) as count
FROM rook_webhook_events
WHERE payload->>'data_structure' = 'activity_event' 
   OR payload->>'dataStructure' = 'activity_event'
GROUP BY activity_type
ORDER BY count DESC
LIMIT 20;
