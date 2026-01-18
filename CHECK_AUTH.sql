-- Check your auth status
SELECT 
    auth.uid() as your_user_id,
    EXISTS (
        SELECT 1 FROM family_members 
        WHERE family_id = 'de510539-b812-4312-9f61-812cec10f8c5'
        AND user_id = auth.uid()
    ) as you_are_in_this_family;

-- Show all members of this family
SELECT 
    fm.first_name,
    fm.user_id,
    fm.user_id = auth.uid() as is_you
FROM family_members fm
WHERE fm.family_id = 'de510539-b812-4312-9f61-812cec10f8c5';
