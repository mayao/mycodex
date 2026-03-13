-- Add user_id to genetic_findings for per-user data isolation
ALTER TABLE genetic_findings ADD COLUMN user_id TEXT REFERENCES users(id);

-- Backfill existing demo/seeded records to the primary user (user-self)
-- Any records without a valid user assignment go to user-self by default
UPDATE genetic_findings
SET user_id = 'user-self'
WHERE user_id IS NULL;
