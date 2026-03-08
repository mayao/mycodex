CREATE TABLE IF NOT EXISTS schema_migration (
  id TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS data_source (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  source_type TEXT NOT NULL,
  source_name TEXT NOT NULL,
  vendor TEXT,
  ingest_channel TEXT NOT NULL,
  source_file TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS import_task (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  data_source_id TEXT NOT NULL REFERENCES data_source(id),
  task_type TEXT NOT NULL,
  task_status TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_file TEXT,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  total_records INTEGER NOT NULL DEFAULT 0,
  success_records INTEGER NOT NULL DEFAULT 0,
  failed_records INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_definition (
  metric_code TEXT PRIMARY KEY,
  metric_name TEXT NOT NULL,
  category TEXT NOT NULL,
  description TEXT NOT NULL,
  canonical_unit TEXT NOT NULL,
  better_direction TEXT NOT NULL,
  reference_range TEXT,
  supported_source_types TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_record (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  data_source_id TEXT NOT NULL REFERENCES data_source(id),
  import_task_id TEXT REFERENCES import_task(id),
  metric_code TEXT NOT NULL REFERENCES metric_definition(metric_code),
  metric_name TEXT NOT NULL,
  category TEXT NOT NULL,
  raw_value TEXT NOT NULL,
  normalized_value REAL,
  unit TEXT NOT NULL,
  reference_range TEXT,
  abnormal_flag TEXT NOT NULL DEFAULT 'unknown',
  sample_time TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_file TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS insight_record (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  metric_code TEXT REFERENCES metric_definition(metric_code),
  category TEXT NOT NULL,
  insight_type TEXT NOT NULL,
  severity TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_file TEXT,
  related_record_ids TEXT,
  disclaimer TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  notes TEXT
);

CREATE TABLE IF NOT EXISTS report_snapshot (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  report_type TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  summary_json TEXT NOT NULL,
  source_type TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_data_source_user_type
  ON data_source (user_id, source_type);

CREATE INDEX IF NOT EXISTS idx_import_task_source
  ON import_task (data_source_id, started_at);

CREATE INDEX IF NOT EXISTS idx_metric_definition_category
  ON metric_definition (category, metric_code);

CREATE INDEX IF NOT EXISTS idx_metric_record_metric_time
  ON metric_record (user_id, metric_code, sample_time);

CREATE INDEX IF NOT EXISTS idx_metric_record_category_time
  ON metric_record (user_id, category, sample_time);

CREATE INDEX IF NOT EXISTS idx_metric_record_source_metric_time
  ON metric_record (source_type, metric_code, sample_time);

CREATE INDEX IF NOT EXISTS idx_insight_record_user_time
  ON insight_record (user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_report_snapshot_user_period
  ON report_snapshot (user_id, report_type, period_start, period_end);
