-- User material library independent from project composition.

CREATE TABLE IF NOT EXISTS user_sources (
    source_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id      UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    user_id        UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    source_type    VARCHAR(20) NOT NULL CHECK (source_type IN ('text', 'file', 'image', 'audio', 'link')),
    name           VARCHAR(300) NOT NULL,
    content_text   TEXT NOT NULL DEFAULT '',
    file_path      TEXT NOT NULL DEFAULT '',
    link_url       TEXT NOT NULL DEFAULT '',
    metadata       JSONB NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_sources_user ON user_sources(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sources_tenant ON user_sources(tenant_id);

