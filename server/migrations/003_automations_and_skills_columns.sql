-- Backfill migration for existing deployments:
-- 1) add skills_used to billing/audit logs
-- 2) create automations table

ALTER TABLE billing_logs
    ADD COLUMN IF NOT EXISTS skills_used JSONB NOT NULL DEFAULT '[]';

ALTER TABLE audit_logs
    ADD COLUMN IF NOT EXISTS skills_used JSONB NOT NULL DEFAULT '[]';

CREATE TABLE IF NOT EXISTS automations (
    automation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    user_id       UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    name          VARCHAR(200) NOT NULL,
    prompt        TEXT NOT NULL,
    skills        JSONB NOT NULL DEFAULT '[]',
    schedule_kind VARCHAR(20) NOT NULL DEFAULT 'interval' CHECK (schedule_kind IN ('interval', 'daily')),
    interval_hours INTEGER NOT NULL DEFAULT 24,
    timezone      VARCHAR(64) NOT NULL DEFAULT 'UTC',
    status        VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'deleted')),
    run_immediately BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_automations_user ON automations(user_id);
CREATE INDEX IF NOT EXISTS idx_automations_tenant ON automations(tenant_id);

CREATE TABLE IF NOT EXISTS automation_runs (
    run_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_id   UUID NOT NULL REFERENCES automations(automation_id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    status          VARCHAR(20) NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed')),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at     TIMESTAMPTZ,
    response_preview TEXT,
    tokens_in       INTEGER NOT NULL DEFAULT 0,
    tokens_out      INTEGER NOT NULL DEFAULT 0,
    cost            DECIMAL(18,6) NOT NULL DEFAULT 0.000000,
    request_id      UUID,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_automation_runs_automation ON automation_runs(automation_id);
CREATE INDEX IF NOT EXISTS idx_automation_runs_user ON automation_runs(user_id);
