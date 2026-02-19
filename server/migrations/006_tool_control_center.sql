-- 006_tool_control_center.sql
-- Tool & Integration Control Center tables

CREATE TABLE IF NOT EXISTS integrations (
    id                 VARCHAR(128) NOT NULL,
    tenant_id          UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    type               VARCHAR(64) NOT NULL,
    display_name       VARCHAR(255) NOT NULL,
    is_enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    status             VARCHAR(32) NOT NULL DEFAULT 'MISSING_CREDENTIALS',
    last_check_at      TIMESTAMPTZ,
    last_error_code    VARCHAR(64) NOT NULL DEFAULT '',
    last_error_message TEXT NOT NULL DEFAULT '',
    created_by         UUID REFERENCES users(user_id),
    updated_by         UUID REFERENCES users(user_id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, id)
);

CREATE INDEX IF NOT EXISTS idx_integrations_tenant_status ON integrations(tenant_id, status);

CREATE TABLE IF NOT EXISTS integration_secrets (
    integration_id     VARCHAR(128) NOT NULL,
    tenant_id          UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    secret_key_name    VARCHAR(128) NOT NULL,
    secret_ciphertext  TEXT NOT NULL,
    secret_last4       VARCHAR(4) NOT NULL DEFAULT '',
    rotated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rotated_by         UUID REFERENCES users(user_id),
    PRIMARY KEY (tenant_id, integration_id, secret_key_name),
    FOREIGN KEY (tenant_id, integration_id) REFERENCES integrations(tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_integration_secrets_tenant_integration ON integration_secrets(tenant_id, integration_id);

CREATE TABLE IF NOT EXISTS tool_status (
    tool_id             VARCHAR(128) NOT NULL,
    tenant_id           UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    is_enabled          BOOLEAN NOT NULL DEFAULT TRUE,
    status              VARCHAR(32) NOT NULL DEFAULT 'WARN',
    last_check_at       TIMESTAMPTZ,
    last_error_code     VARCHAR(64) NOT NULL DEFAULT '',
    last_error_message  TEXT NOT NULL DEFAULT '',
    created_by          UUID REFERENCES users(user_id),
    updated_by          UUID REFERENCES users(user_id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, tool_id)
);

CREATE INDEX IF NOT EXISTS idx_tool_status_tenant_status ON tool_status(tenant_id, status);
