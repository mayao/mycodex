ALTER TABLE users ADD COLUMN merged_into_user_id TEXT REFERENCES users(id);
ALTER TABLE users ADD COLUMN is_disabled INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_users_merged_target ON users(merged_into_user_id);
CREATE INDEX IF NOT EXISTS idx_users_disabled ON users(is_disabled);

CREATE TABLE IF NOT EXISTS user_identity (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  provider TEXT NOT NULL,
  provider_subject TEXT NOT NULL,
  email TEXT,
  claims_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  origin_server_id TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_identity_provider_subject
  ON user_identity(provider, provider_subject);

CREATE INDEX IF NOT EXISTS idx_user_identity_user
  ON user_identity(user_id);

CREATE INDEX IF NOT EXISTS idx_user_identity_updated_at
  ON user_identity(updated_at);

INSERT OR IGNORE INTO user_identity (
  id,
  user_id,
  provider,
  provider_subject,
  email,
  claims_json,
  created_at,
  updated_at,
  origin_server_id
)
SELECT
  'identity::phone::' || phone_number,
  id,
  'phone',
  phone_number,
  NULL,
  NULL,
  COALESCE(NULLIF(created_at, ''), CURRENT_TIMESTAMP),
  COALESCE(updated_at, NULLIF(created_at, ''), CURRENT_TIMESTAMP),
  COALESCE(origin_server_id, (SELECT value FROM app_meta WHERE key = 'server_id'))
FROM users
WHERE phone_number IS NOT NULL
  AND trim(phone_number) != '';

INSERT OR IGNORE INTO user_identity (
  id,
  user_id,
  provider,
  provider_subject,
  email,
  claims_json,
  created_at,
  updated_at,
  origin_server_id
)
SELECT
  'identity::device::' || lower(device_id),
  id,
  'device',
  lower(device_id),
  NULL,
  NULL,
  COALESCE(NULLIF(created_at, ''), CURRENT_TIMESTAMP),
  COALESCE(updated_at, NULLIF(created_at, ''), CURRENT_TIMESTAMP),
  COALESCE(origin_server_id, (SELECT value FROM app_meta WHERE key = 'server_id'))
FROM users
WHERE device_id IS NOT NULL
  AND trim(device_id) != '';
