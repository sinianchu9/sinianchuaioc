-- Role/Task use-cases + project sources + output artifacts (MVP)

CREATE TABLE IF NOT EXISTS projects (
    project_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    user_id       UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    name          VARCHAR(200) NOT NULL,
    description   TEXT NOT NULL DEFAULT '',
    status        VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'deleted')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_projects_user ON projects(user_id);
CREATE INDEX IF NOT EXISTS idx_projects_tenant ON projects(tenant_id);

CREATE TABLE IF NOT EXISTS project_sources (
    source_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id     UUID NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    tenant_id      UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    user_id        UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    source_type    VARCHAR(20) NOT NULL CHECK (source_type IN ('text', 'file', 'image', 'audio', 'link')),
    name           VARCHAR(300) NOT NULL,
    content_text   TEXT NOT NULL DEFAULT '',
    file_path      TEXT NOT NULL DEFAULT '',
    link_url       TEXT NOT NULL DEFAULT '',
    metadata       JSONB NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_project_sources_project ON project_sources(project_id);
CREATE INDEX IF NOT EXISTS idx_project_sources_user ON project_sources(user_id);

CREATE TABLE IF NOT EXISTS project_artifacts (
    artifact_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id     UUID NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    tenant_id      UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    user_id        UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    run_id         UUID NOT NULL,
    role_id        VARCHAR(80) NOT NULL DEFAULT '',
    task_id        VARCHAR(120) NOT NULL DEFAULT '',
    output_type    VARCHAR(20) NOT NULL,
    filename       VARCHAR(300) NOT NULL,
    storage_path   TEXT NOT NULL,
    size_bytes     BIGINT NOT NULL DEFAULT 0,
    sha256         VARCHAR(64) NOT NULL DEFAULT '',
    metadata       JSONB NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_project_artifacts_project ON project_artifacts(project_id);
CREATE INDEX IF NOT EXISTS idx_project_artifacts_user ON project_artifacts(user_id);
CREATE INDEX IF NOT EXISTS idx_project_artifacts_run ON project_artifacts(run_id);
