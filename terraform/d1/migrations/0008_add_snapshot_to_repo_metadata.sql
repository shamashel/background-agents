-- Add snapshot_image_id column to repo_metadata table
-- This enables cross-session snapshot reuse
ALTER TABLE repo_metadata ADD COLUMN snapshot_image_id TEXT;

-- Index for fast lookup by snapshot_image_id
CREATE INDEX IF NOT EXISTS idx_repo_metadata_snapshot ON repo_metadata(snapshot_image_id);
