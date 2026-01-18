-- Query 1: Your family info
SELECT 
    fm.family_id,
    fm.first_name,
    fm.role
FROM family_members fm
WHERE fm.user_id = auth.uid();
