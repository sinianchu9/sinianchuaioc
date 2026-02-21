-- Phase 2 Adaptive Workspace: add temporary project flag

ALTER TABLE projects ADD COLUMN is_temporary BOOLEAN NOT NULL DEFAULT false;

-- Add index to help with periodic cleanup of temporary projects
CREATE INDEX IF NOT EXISTS idx_projects_temporary ON projects(is_temporary) WHERE is_temporary = true;
