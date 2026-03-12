-- Add device-based authentication support
-- Users can now be identified by their device UUID instead of phone number

ALTER TABLE users ADD COLUMN device_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_device ON users(device_id) WHERE device_id IS NOT NULL;
