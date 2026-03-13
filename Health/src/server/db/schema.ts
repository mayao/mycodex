import type { DatabaseSync } from "node:sqlite";

export const schemaSql = `
CREATE TABLE IF NOT EXISTS app_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  sex TEXT NOT NULL,
  birth_year INTEGER NOT NULL,
  height_cm REAL NOT NULL,
  note TEXT
);

CREATE TABLE IF NOT EXISTS data_sources (
  id TEXT PRIMARY KEY,
  source_type TEXT NOT NULL,
  name TEXT NOT NULL,
  vendor TEXT,
  ingest_channel TEXT NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS import_batches (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES data_sources(id),
  file_name TEXT,
  imported_at TEXT NOT NULL,
  content_hash TEXT,
  note TEXT
);

CREATE TABLE IF NOT EXISTS metric_catalog (
  code TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  short_label TEXT NOT NULL,
  category TEXT NOT NULL,
  default_unit TEXT NOT NULL,
  better_direction TEXT NOT NULL,
  normal_low REAL,
  normal_high REAL,
  reference_text TEXT,
  description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS measurement_sets (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  source_id TEXT NOT NULL REFERENCES data_sources(id),
  import_batch_id TEXT REFERENCES import_batches(id),
  set_kind TEXT NOT NULL,
  title TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  report_date TEXT,
  note TEXT,
  raw_payload_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS measurements (
  id TEXT PRIMARY KEY,
  measurement_set_id TEXT NOT NULL REFERENCES measurement_sets(id) ON DELETE CASCADE,
  metric_code TEXT NOT NULL REFERENCES metric_catalog(code),
  raw_value_text TEXT,
  value_numeric REAL NOT NULL,
  unit TEXT NOT NULL,
  normalized_value REAL NOT NULL,
  normalized_unit TEXT NOT NULL,
  reference_low REAL,
  reference_high REAL,
  abnormal_flag TEXT,
  note TEXT,
  source_label TEXT,
  UNIQUE (measurement_set_id, metric_code)
);

CREATE TABLE IF NOT EXISTS genetic_findings (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id),
  source_id TEXT NOT NULL REFERENCES data_sources(id),
  gene_symbol TEXT NOT NULL,
  variant_id TEXT NOT NULL,
  trait_code TEXT NOT NULL,
  risk_level TEXT NOT NULL,
  evidence_level TEXT NOT NULL,
  summary TEXT NOT NULL,
  suggestion TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  raw_payload_json TEXT
);

CREATE TABLE IF NOT EXISTS rule_events (
  id TEXT PRIMARY KEY,
  rule_code TEXT NOT NULL,
  severity TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  disclaimer TEXT NOT NULL,
  measurement_set_id TEXT REFERENCES measurement_sets(id),
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS report_snapshots (
  id TEXT PRIMARY KEY,
  period_kind TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  summary_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_measurement_sets_kind_date
  ON measurement_sets (set_kind, recorded_at);

CREATE INDEX IF NOT EXISTS idx_measurements_metric_code
  ON measurements (metric_code);

CREATE INDEX IF NOT EXISTS idx_measurements_set_id
  ON measurements (measurement_set_id);
`;

export function applySchema(database: DatabaseSync): void {
  database.exec(schemaSql);
}
