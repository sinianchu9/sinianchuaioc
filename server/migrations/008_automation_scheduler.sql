-- Migration 008: Add last_run_at to automations for scheduler tracking
-- Scheduler uses this column to decide whether an automation is due.
-- NULL means never run (always due if active).

ALTER TABLE automations
    ADD COLUMN IF NOT EXISTS last_run_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_automations_scheduler
    ON automations (status, last_run_at)
    WHERE status = 'active';
