-- Normalize legacy health_conditions values to granular WHO types (no deletes)
-- Run in Supabase SQL editor

begin;

-- Inspect current data
select condition_type, count(*) from health_conditions group by 1;

-- Map legacy/general values to new granular set
update health_conditions set condition_type = 'bp_elevated_untreated' where condition_type = 'hypertension';
update health_conditions set condition_type = 'diabetes_unknown'        where condition_type = 'diabetes';
update health_conditions set condition_type = 'high_cholesterol'       where condition_type = 'cholesterol';
update health_conditions set condition_type = 'prior_heart_attack'     where condition_type = 'prior_heart_stroke';
update health_conditions set condition_type = 'chronic_kidney_disease' where condition_type = 'ckd';
update health_conditions set condition_type = 'family_history_heart_early'    where condition_type = 'family_history_heart';
update health_conditions set condition_type = 'family_history_stroke_early'   where condition_type = 'family_history_stroke';
update health_conditions set condition_type = 'family_history_type2_diabetes' where condition_type = 'family_history_diabetes';

-- Park any remaining unknowns
update health_conditions
set condition_type = 'heart_health_unsure'
where condition_type not in (
    'bp_normal','bp_elevated_untreated','bp_elevated_treated','bp_unknown',
    'diabetes_none','diabetes_pre_diabetic','diabetes_type_1','diabetes_type_2','diabetes_unknown',
    'prior_heart_attack','prior_stroke',
    'family_history_heart_early','family_history_stroke_early','family_history_type2_diabetes',
    'chronic_kidney_disease','atrial_fibrillation','high_cholesterol',
    'heart_health_unsure','medical_history_unsure'
);

-- Reapply constraint
alter table health_conditions drop constraint if exists health_conditions_condition_type_check;
alter table health_conditions add constraint health_conditions_condition_type_check
check (condition_type in (
    'bp_normal','bp_elevated_untreated','bp_elevated_treated','bp_unknown',
    'diabetes_none','diabetes_pre_diabetic','diabetes_type_1','diabetes_type_2','diabetes_unknown',
    'prior_heart_attack','prior_stroke',
    'family_history_heart_early','family_history_stroke_early','family_history_type2_diabetes',
    'chronic_kidney_disease','atrial_fibrillation','high_cholesterol',
    'heart_health_unsure','medical_history_unsure'
));

commit;

