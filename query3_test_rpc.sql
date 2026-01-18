-- Query 3: Test the RPC
-- REPLACE 'YOUR_FAMILY_ID_HERE' with the family_id from Query 1

SELECT * FROM get_family_vitality('YOUR_FAMILY_ID_HERE'::uuid);
