CREATE TEMP TABLE tmp_user_scoped_data_source_map AS
SELECT DISTINCT
  metric_record.data_source_id AS old_id,
  metric_record.user_id AS user_id,
  metric_record.source_type AS source_type,
  'data-source::' || metric_record.user_id || '::' || metric_record.source_type AS new_id
FROM metric_record
WHERE metric_record.data_source_id LIKE 'data-source::%'
  AND metric_record.data_source_id NOT LIKE 'data-source::%::%'

UNION

SELECT DISTINCT
  import_task.data_source_id AS old_id,
  import_task.user_id AS user_id,
  import_task.source_type AS source_type,
  'data-source::' || import_task.user_id || '::' || import_task.source_type AS new_id
FROM import_task
WHERE import_task.data_source_id LIKE 'data-source::%'
  AND import_task.data_source_id NOT LIKE 'data-source::%::%'

UNION

SELECT DISTINCT
  data_source.id AS old_id,
  data_source.user_id AS user_id,
  data_source.source_type AS source_type,
  'data-source::' || data_source.user_id || '::' || data_source.source_type AS new_id
FROM data_source
WHERE data_source.id LIKE 'data-source::%'
  AND data_source.id NOT LIKE 'data-source::%::%';

INSERT OR REPLACE INTO data_source (
  id,
  user_id,
  source_type,
  source_name,
  vendor,
  ingest_channel,
  source_file,
  notes,
  created_at,
  updated_at,
  origin_server_id
)
SELECT
  map.new_id,
  map.user_id,
  COALESCE(data_source.source_type, map.source_type),
  data_source.source_name,
  data_source.vendor,
  data_source.ingest_channel,
  data_source.source_file,
  data_source.notes,
  data_source.created_at,
  CURRENT_TIMESTAMP,
  data_source.origin_server_id
FROM tmp_user_scoped_data_source_map AS map
JOIN data_source ON data_source.id = map.old_id;

UPDATE metric_record
SET data_source_id = (
  SELECT new_id
  FROM tmp_user_scoped_data_source_map AS map
  WHERE map.old_id = metric_record.data_source_id
    AND map.user_id = metric_record.user_id
)
WHERE EXISTS (
  SELECT 1
  FROM tmp_user_scoped_data_source_map AS map
  WHERE map.old_id = metric_record.data_source_id
    AND map.user_id = metric_record.user_id
);

UPDATE import_task
SET data_source_id = (
  SELECT new_id
  FROM tmp_user_scoped_data_source_map AS map
  WHERE map.old_id = import_task.data_source_id
    AND map.user_id = import_task.user_id
)
WHERE EXISTS (
  SELECT 1
  FROM tmp_user_scoped_data_source_map AS map
  WHERE map.old_id = import_task.data_source_id
    AND map.user_id = import_task.user_id
);

DELETE FROM data_source
WHERE id IN (
  SELECT DISTINCT old_id
  FROM tmp_user_scoped_data_source_map
  WHERE old_id != new_id
);

DROP TABLE tmp_user_scoped_data_source_map;
