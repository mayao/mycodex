CREATE TABLE IF NOT EXISTS import_row_log (
  id TEXT PRIMARY KEY,
  import_task_id TEXT NOT NULL REFERENCES import_task(id) ON DELETE CASCADE,
  row_number INTEGER NOT NULL,
  row_status TEXT NOT NULL,
  metric_code TEXT,
  source_field TEXT,
  error_message TEXT,
  raw_payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_import_row_log_task_status
  ON import_row_log (import_task_id, row_status, row_number);
