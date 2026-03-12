-- Health Plan system: AI-generated suggestions → user-accepted plan items → daily completion tracking

CREATE TABLE IF NOT EXISTS health_suggestion_batch (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  data_window_days INTEGER NOT NULL DEFAULT 7,
  provider TEXT NOT NULL DEFAULT 'anthropic',
  model TEXT NOT NULL DEFAULT 'claude-sonnet-4-20250514',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS health_suggestion (
  id TEXT PRIMARY KEY,
  batch_id TEXT NOT NULL REFERENCES health_suggestion_batch(id),
  dimension TEXT NOT NULL,           -- exercise / diet / sleep / checkup
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  target_metric_code TEXT,           -- nullable: maps to metric_definition.metric_code
  target_value REAL,
  target_unit TEXT,
  frequency TEXT NOT NULL DEFAULT 'daily',  -- daily / weekly / once
  time_hint TEXT,                    -- e.g. "07:00" or "morning"
  priority INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS health_plan_item (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  suggestion_id TEXT REFERENCES health_suggestion(id),
  dimension TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  target_metric_code TEXT,
  target_value REAL,
  target_unit TEXT,
  frequency TEXT NOT NULL DEFAULT 'daily',
  time_hint TEXT,
  status TEXT NOT NULL DEFAULT 'active',  -- active / paused / completed / archived
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS health_plan_check (
  id TEXT PRIMARY KEY,
  plan_item_id TEXT NOT NULL REFERENCES health_plan_item(id),
  check_date TEXT NOT NULL,          -- YYYY-MM-DD
  actual_value REAL,
  is_completed INTEGER NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT 'manual',   -- auto / manual
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(plan_item_id, check_date)
);

CREATE INDEX IF NOT EXISTS idx_suggestion_batch_user ON health_suggestion_batch(user_id);
CREATE INDEX IF NOT EXISTS idx_suggestion_batch_id ON health_suggestion(batch_id);
CREATE INDEX IF NOT EXISTS idx_plan_item_user_status ON health_plan_item(user_id, status);
CREATE INDEX IF NOT EXISTS idx_plan_check_item_date ON health_plan_check(plan_item_id, check_date);
