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
  updated_at
)
SELECT
  ds.id,
  'user-self',
  ds.source_type,
  ds.name,
  ds.vendor,
  ds.ingest_channel,
  NULL,
  ds.note,
  COALESCE(ds.created_at, CURRENT_TIMESTAMP),
  COALESCE(ds.created_at, CURRENT_TIMESTAMP)
FROM data_sources ds;

INSERT OR REPLACE INTO metric_definition (
  metric_code,
  metric_name,
  category,
  description,
  canonical_unit,
  better_direction,
  reference_range,
  supported_source_types,
  is_active,
  created_at,
  updated_at
)
SELECT
  mc.code,
  mc.label,
  CASE
    WHEN mc.category = 'body' THEN 'body_composition'
    WHEN mc.category = 'lipid' THEN 'lipid'
    WHEN mc.category = 'activity' THEN 'activity'
    WHEN mc.category = 'sleep' THEN 'sleep'
    ELSE 'lab'
  END,
  mc.description,
  mc.default_unit,
  mc.better_direction,
  CASE
    WHEN mc.reference_text IS NOT NULL THEN mc.reference_text
    WHEN mc.normal_low IS NOT NULL AND mc.normal_high IS NOT NULL THEN CAST(mc.normal_low AS TEXT) || ' - ' || CAST(mc.normal_high AS TEXT)
    WHEN mc.normal_low IS NOT NULL THEN '>= ' || CAST(mc.normal_low AS TEXT)
    WHEN mc.normal_high IS NOT NULL THEN '<= ' || CAST(mc.normal_high AS TEXT)
    ELSE NULL
  END,
  COALESCE((
    SELECT group_concat(DISTINCT ds.source_type)
    FROM measurements m
    JOIN measurement_sets ms ON ms.id = m.measurement_set_id
    JOIN data_sources ds ON ds.id = ms.source_id
    WHERE m.metric_code = mc.code
  ), 'mock'),
  1,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM metric_catalog mc;

INSERT OR REPLACE INTO import_task (
  id,
  user_id,
  data_source_id,
  task_type,
  task_status,
  source_type,
  source_file,
  started_at,
  finished_at,
  total_records,
  success_records,
  failed_records,
  notes,
  created_at
)
SELECT
  'import::' || ms.id,
  ms.user_id,
  ms.source_id,
  CASE
    WHEN ds.ingest_channel = 'manual' THEN 'manual_backfill'
    WHEN ds.ingest_channel = 'file' THEN 'file_backfill'
    ELSE 'mock_backfill'
  END,
  'completed',
  ds.source_type,
  COALESCE(ib.file_name, REPLACE(ms.title, ' ', '_') || '.mock.json'),
  ms.recorded_at,
  COALESCE(ms.created_at, ms.recorded_at),
  COUNT(m.id),
  COUNT(m.id),
  0,
  COALESCE(ms.note, ib.note),
  COALESCE(ms.created_at, CURRENT_TIMESTAMP)
FROM measurement_sets ms
JOIN data_sources ds ON ds.id = ms.source_id
LEFT JOIN import_batches ib ON ib.id = ms.import_batch_id
LEFT JOIN measurements m ON m.measurement_set_id = ms.id
GROUP BY
  ms.id,
  ms.user_id,
  ms.source_id,
  ds.ingest_channel,
  ds.source_type,
  ib.file_name,
  ms.title,
  ms.recorded_at,
  ms.created_at,
  ms.note,
  ib.note;

INSERT OR REPLACE INTO metric_record (
  id,
  user_id,
  data_source_id,
  import_task_id,
  metric_code,
  metric_name,
  category,
  raw_value,
  normalized_value,
  unit,
  reference_range,
  abnormal_flag,
  sample_time,
  source_type,
  source_file,
  notes,
  created_at
)
SELECT
  'record::' || m.id,
  ms.user_id,
  ms.source_id,
  'import::' || ms.id,
  m.metric_code,
  mc.label,
  CASE
    WHEN mc.category = 'body' THEN 'body_composition'
    WHEN mc.category = 'lipid' THEN 'lipid'
    WHEN mc.category = 'activity' THEN 'activity'
    WHEN mc.category = 'sleep' THEN 'sleep'
    ELSE 'lab'
  END,
  COALESCE(m.raw_value_text, CAST(m.value_numeric AS TEXT)),
  m.normalized_value,
  COALESCE(NULLIF(m.normalized_unit, ''), m.unit),
  CASE
    WHEN m.reference_low IS NOT NULL AND m.reference_high IS NOT NULL THEN CAST(m.reference_low AS TEXT) || ' - ' || CAST(m.reference_high AS TEXT)
    WHEN m.reference_low IS NOT NULL THEN '>= ' || CAST(m.reference_low AS TEXT)
    WHEN m.reference_high IS NOT NULL THEN '<= ' || CAST(m.reference_high AS TEXT)
    ELSE CASE
      WHEN mc.reference_text IS NOT NULL THEN mc.reference_text
      ELSE NULL
    END
  END,
  COALESCE(NULLIF(m.abnormal_flag, ''), 'unknown'),
  ms.recorded_at,
  ds.source_type,
  COALESCE(ib.file_name, REPLACE(ms.title, ' ', '_') || '.mock.json'),
  COALESCE(m.note, ms.note),
  COALESCE(ms.created_at, CURRENT_TIMESTAMP)
FROM measurements m
JOIN measurement_sets ms ON ms.id = m.measurement_set_id
JOIN metric_catalog mc ON mc.code = m.metric_code
JOIN data_sources ds ON ds.id = ms.source_id
LEFT JOIN import_batches ib ON ib.id = ms.import_batch_id;
