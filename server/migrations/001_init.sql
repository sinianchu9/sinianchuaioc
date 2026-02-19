-- AIOC Database Schema v1.0
-- PostgreSQL migrations

-- ==========================================
-- 1. Tenants (租户)
-- ==========================================
CREATE TABLE IF NOT EXISTS tenants (
    tenant_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(255) NOT NULL,
    type         VARCHAR(20) NOT NULL DEFAULT 'individual' CHECK (type IN ('individual', 'enterprise')),
    plan_level   VARCHAR(20) NOT NULL DEFAULT 'free' CHECK (plan_level IN ('free', 'pro', 'team', 'enterprise')),
    balance      DECIMAL(18,6) NOT NULL DEFAULT 0.000000,
    status       VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    license_key  VARCHAR(255),
    ip_whitelist TEXT[],
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 2. Users (用户)
-- ==========================================
CREATE TABLE IF NOT EXISTS users (
    user_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    email         VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    display_name  VARCHAR(100),
    roles         TEXT[] NOT NULL DEFAULT ARRAY['user'],
    status        VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_tenant ON users(tenant_id);
CREATE INDEX idx_users_email ON users(email);

-- ==========================================
-- 3. Client Registry (客户端注册表)
-- ==========================================
CREATE TABLE IF NOT EXISTS client_registry (
    client_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(100) NOT NULL,
    platform       VARCHAR(50) NOT NULL CHECK (platform IN ('macos', 'windows', 'ios', 'android', 'web', 'cli')),
    min_version    VARCHAR(20) NOT NULL DEFAULT '1.0.0',
    feature_flags  JSONB NOT NULL DEFAULT '{}',
    status         VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'blocked')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 4. Sessions (会话)
-- ==========================================
CREATE TABLE IF NOT EXISTS sessions (
    session_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    title        VARCHAR(500) NOT NULL DEFAULT 'New Chat',
    model_mode   VARCHAR(20) NOT NULL DEFAULT 'economy' CHECK (model_mode IN ('economy', 'precision', 'privacy')),
    messages     JSONB NOT NULL DEFAULT '[]',
    token_count  INTEGER NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user ON sessions(user_id);

-- ==========================================
-- 5. Billing Logs (计费日志)
-- ==========================================
CREATE TABLE IF NOT EXISTS billing_logs (
    id           BIGSERIAL PRIMARY KEY,
    tenant_id    UUID NOT NULL REFERENCES tenants(tenant_id),
    user_id      UUID NOT NULL REFERENCES users(user_id),
    ts           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    model        VARCHAR(100) NOT NULL,
    tokens_in    INTEGER NOT NULL DEFAULT 0,
    tokens_out   INTEGER NOT NULL DEFAULT 0,
    cost         DECIMAL(18,6) NOT NULL DEFAULT 0.000000,
    request_id   UUID NOT NULL UNIQUE,
    client_id    UUID,
    session_id   UUID,
    skills_used  JSONB NOT NULL DEFAULT '[]'
);

CREATE INDEX idx_billing_tenant ON billing_logs(tenant_id);
CREATE INDEX idx_billing_user ON billing_logs(user_id);
CREATE INDEX idx_billing_ts ON billing_logs(ts);

-- ==========================================
-- 6. Audit Logs (审计日志)
-- ==========================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id                BIGSERIAL PRIMARY KEY,
    tenant_id         UUID NOT NULL REFERENCES tenants(tenant_id),
    user_id           UUID NOT NULL REFERENCES users(user_id),
    ts                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    prompt_snapshot   TEXT,
    response_snapshot TEXT,
    model_used        VARCHAR(100) NOT NULL,
    tokens_in         INTEGER NOT NULL DEFAULT 0,
    tokens_out        INTEGER NOT NULL DEFAULT 0,
    cost              DECIMAL(18,6) NOT NULL DEFAULT 0.000000,
    tools_called      JSONB DEFAULT '[]',
    client_id         UUID,
    trace_id          VARCHAR(64) NOT NULL,
    fallback_used     BOOLEAN NOT NULL DEFAULT FALSE,
    session_id        UUID,
    skills_used       JSONB NOT NULL DEFAULT '[]'
);

CREATE INDEX idx_audit_tenant ON audit_logs(tenant_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_ts ON audit_logs(ts);
CREATE INDEX idx_audit_trace ON audit_logs(trace_id);

-- ==========================================
-- 7. Routing Rules (路由规则)
-- ==========================================
CREATE TABLE IF NOT EXISTS routing_rules (
    rule_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(100) NOT NULL,
    condition_expr VARCHAR(500),
    target_model   VARCHAR(100) NOT NULL,
    mode           VARCHAR(20) NOT NULL CHECK (mode IN ('economy', 'precision', 'privacy')),
    max_tokens     INTEGER NOT NULL DEFAULT 4096,
    priority       INTEGER NOT NULL DEFAULT 0,
    enabled        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 8. Plans (套餐定义)
-- ==========================================
CREATE TABLE IF NOT EXISTS plans (
    plan_id      VARCHAR(20) PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    price_monthly DECIMAL(18,6) NOT NULL DEFAULT 0.000000,
    token_quota  BIGINT NOT NULL DEFAULT 0,       -- 0 = unlimited for enterprise
    features     JSONB NOT NULL DEFAULT '{}',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 9. Automations (自动化任务)
-- ==========================================
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

CREATE INDEX idx_automations_user ON automations(user_id);
CREATE INDEX idx_automations_tenant ON automations(tenant_id);

-- ==========================================
-- 10. Automation Runs (自动化执行记录)
-- ==========================================
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

CREATE INDEX idx_automation_runs_automation ON automation_runs(automation_id);
CREATE INDEX idx_automation_runs_user ON automation_runs(user_id);
