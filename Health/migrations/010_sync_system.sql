-- 010_sync_system.sql
-- Multi-server data synchronization support

-- Step 1: Ensure server_id exists in app_meta
INSERT OR IGNORE INTO app_meta (key, value)
  VALUES ('server_id', lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6))));

-- Step 2: Add updated_at and origin_server_id to syncable tables
-- NOTE: SQLite ALTER TABLE does not allow DEFAULT with non-constant values.
-- We add columns as plain TEXT, then backfill via UPDATE.

-- users
ALTER TABLE users ADD COLUMN updated_at TEXT;
ALTER TABLE users ADD COLUMN origin_server_id TEXT;
UPDATE users SET updated_at = COALESCE(created_at, datetime('now')), origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE updated_at IS NULL;

-- metric_record
ALTER TABLE metric_record ADD COLUMN updated_at TEXT;
ALTER TABLE metric_record ADD COLUMN origin_server_id TEXT;
UPDATE metric_record SET updated_at = COALESCE(created_at, datetime('now')), origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- data_source (already has updated_at)
ALTER TABLE data_source ADD COLUMN origin_server_id TEXT;
UPDATE data_source SET origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- import_task
ALTER TABLE import_task ADD COLUMN updated_at TEXT;
ALTER TABLE import_task ADD COLUMN origin_server_id TEXT;
UPDATE import_task SET updated_at = COALESCE(created_at, datetime('now')), origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- metric_definition (already has updated_at)
ALTER TABLE metric_definition ADD COLUMN origin_server_id TEXT;
UPDATE metric_definition SET origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- insight_record
ALTER TABLE insight_record ADD COLUMN updated_at TEXT;
ALTER TABLE insight_record ADD COLUMN origin_server_id TEXT;
UPDATE insight_record SET updated_at = COALESCE(created_at, datetime('now')), origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- report_snapshot
ALTER TABLE report_snapshot ADD COLUMN updated_at TEXT;
ALTER TABLE report_snapshot ADD COLUMN origin_server_id TEXT;
UPDATE report_snapshot SET updated_at = COALESCE(created_at, datetime('now')), origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- health_suggestion_batch
ALTER TABLE health_suggestion_batch ADD COLUMN updated_at TEXT;
ALTER TABLE health_suggestion_batch ADD COLUMN origin_server_id TEXT;
UPDATE health_suggestion_batch SET updated_at = COALESCE(created_at, datetime('now')), origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- health_suggestion
ALTER TABLE health_suggestion ADD COLUMN updated_at TEXT;
ALTER TABLE health_suggestion ADD COLUMN origin_server_id TEXT;
UPDATE health_suggestion SET updated_at = COALESCE(created_at, datetime('now')), origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- health_plan_item (already has updated_at)
ALTER TABLE health_plan_item ADD COLUMN origin_server_id TEXT;
UPDATE health_plan_item SET origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- health_plan_check
ALTER TABLE health_plan_check ADD COLUMN updated_at TEXT;
ALTER TABLE health_plan_check ADD COLUMN origin_server_id TEXT;
UPDATE health_plan_check SET updated_at = COALESCE(created_at, datetime('now')), origin_server_id = (SELECT value FROM app_meta WHERE key = 'server_id') WHERE origin_server_id IS NULL;

-- Step 3: New tables for sync coordination

CREATE TABLE IF NOT EXISTS sync_peer (
  server_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  last_sync_at TEXT,
  last_sync_cursor TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sync_log (
  id TEXT PRIMARY KEY,
  peer_server_id TEXT NOT NULL,
  direction TEXT NOT NULL,
  tables_synced TEXT NOT NULL,
  rows_received INTEGER NOT NULL DEFAULT 0,
  rows_sent INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  error_message TEXT,
  started_at TEXT NOT NULL,
  finished_at TEXT NOT NULL
);

-- Step 4: Indexes for sync queries
CREATE INDEX IF NOT EXISTS idx_users_updated_at ON users(updated_at);
CREATE INDEX IF NOT EXISTS idx_metric_record_updated_at ON metric_record(updated_at);
CREATE INDEX IF NOT EXISTS idx_data_source_updated_at ON data_source(updated_at);
CREATE INDEX IF NOT EXISTS idx_import_task_updated_at ON import_task(updated_at);
CREATE INDEX IF NOT EXISTS idx_insight_record_updated_at ON insight_record(updated_at);
CREATE INDEX IF NOT EXISTS idx_report_snapshot_updated_at ON report_snapshot(updated_at);
CREATE INDEX IF NOT EXISTS idx_health_suggestion_batch_updated_at ON health_suggestion_batch(updated_at);
CREATE INDEX IF NOT EXISTS idx_health_suggestion_updated_at ON health_suggestion(updated_at);
CREATE INDEX IF NOT EXISTS idx_health_plan_item_updated_at ON health_plan_item(updated_at);
CREATE INDEX IF NOT EXISTS idx_health_plan_check_updated_at ON health_plan_check(updated_at);
CREATE INDEX IF NOT EXISTS idx_sync_log_peer ON sync_log(peer_server_id, finished_at);
