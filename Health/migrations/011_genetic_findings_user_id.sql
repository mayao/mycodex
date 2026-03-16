-- Backfill existing demo/seeded records to the primary user (user-self)
-- Note: the user_id column is already defined in the base schema (schema.ts).
-- This migration originally included ALTER TABLE ADD COLUMN, but that fails
-- on fresh databases where the column already exists from CREATE TABLE.
UPDATE genetic_findings
SET user_id = 'user-self'
WHERE user_id IS NULL;
