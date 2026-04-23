-- Extend connected_wearables.wearable_type to allow Garmin (matches Swift WearableType + DataManager allowlist).

ALTER TABLE public.connected_wearables
  DROP CONSTRAINT IF EXISTS connected_wearables_wearable_type_check;

ALTER TABLE public.connected_wearables
  ADD CONSTRAINT connected_wearables_wearable_type_check
  CHECK (
    wearable_type = ANY (
      ARRAY[
        'appleWatch'::text,
        'whoop'::text,
        'oura'::text,
        'fitbit'::text,
        'garmin'::text
      ]
    )
  );
