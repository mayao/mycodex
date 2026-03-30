UPDATE metric_definition
SET category = 'diet',
    updated_at = CURRENT_TIMESTAMP
WHERE metric_code IN ('diet.calories_intake_kcal', 'diet.meal_upload_count');

UPDATE metric_record
SET category = 'diet'
WHERE metric_code IN ('diet.calories_intake_kcal', 'diet.meal_upload_count');
