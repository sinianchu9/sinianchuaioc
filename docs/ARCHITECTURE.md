# AIOC Architecture

## 1. Product Shape

AIOC is a multi-user SaaS wrapper around OpenClaw.
Target value: users access capabilities with minimal setup, while platform handles auth, billing, policy, and audit.

Core principle: **Skills over Models**, upgraded from **Role -> Task -> Skills** to **Role -> Workflow Skill -> Verifiable Execution**.

## 2. Runtime Topology

`Flutter Client -> Gateway (Go) -> Core (Go) -> Engine OpenClaw (Node/TS) -> LLM Providers/Tools`

Supporting services:

- PostgreSQL: users, sessions, billing, audit, automations, automation runs, projects, project_sources, project_artifacts.
- Redis: rate limiting and cost circuit breaker state.

## 3. Service Responsibilities

### Gateway (`server/gateway-go`)

- JWT auth and refresh.
- plan/client checks and access guardrails.
- billing pre-check and rate/cost limiting.
- public API surface (`/auth`, `/chat`, `/sessions`, `/billing`, `/client`, `/automations`, `/projects`).
- chat stream proxy into core.
- configuration center inputs (new):
  - tooling manifest: `server/gateway-go/config/openclaw_tooling_manifest.json`
  - status panel payload template: `server/gateway-go/config/config_center_status_panel.template.json`
- configuration center admin APIs (new):
  - `GET /api/v1/admin/config-center/manifest`
  - `GET /api/v1/admin/config-center/status`
  - `POST /api/v1/admin/config-center/validate`
  - `PATCH /api/v1/admin/config-center/integrations/:id`
- tool & integration control center (new):
  - manifest-driven dependency graph: `server/gateway-go/config/tools.manifest.yaml`
  - tenant-scoped status and secret storage: `integrations`, `integration_secrets`, `tool_status`
  - encrypted secret storage using AES-GCM (key from `MASTER_KEY`)
  - admin APIs:
    - `GET /api/v1/admin/tools`
    - `GET /api/v1/admin/tools/:id`
    - `POST /api/v1/admin/tools/:id/toggle`
    - `GET /api/v1/admin/integrations`
    - `GET /api/v1/admin/integrations/:id`
    - `POST /api/v1/admin/integrations/:id/secret`
    - `POST /api/v1/admin/integrations/:id/check`
    - `GET /api/v1/admin/status/summary`

### Core (`server/core-go`)

- request orchestration and model routing.
- skill-to-tool policy derivation (`plan + skills -> allowed_tools`).
- role/task/project context injection into system prompt.
- workflow contract loading and validation (planned):
  - required step types (`query`, `generate`, `action`)
  - required tool calls
  - required artifact/action outputs
- project source loading from DB and handoff to engine (`project_sources`).
- billing + audit + Session history persistence (`sessions.messages`) and session detail API.
- Session-Project Isolation: sessions are strictly scoped to project IDs; switching projects resets the active session state.
- Global Draft Chat: dedicated UI entry for managing non-project specific history.
- Stop-generation support for stream interruption.
- project artifact persistence (`project_artifacts`) from engine tool results.
- engine SPI orchestration and SSE event normalization.
- runtime integration credential injection:
  - load tenant-scoped secret records from `integration_secrets`
  - decrypt with `MASTER_KEY` in core
  - pass allowlisted runtime keys to engine through `integration_env`

### Engine OpenClaw (`server/engine-openclaw`)

- OpenClaw execution runtime and tool loop.
- tool safety policy enforcement.
- workflow step execution and step-level evidence emission (planned).
- scenario execution tools:
  - `source_lookup`
  - `artifact_render`
  - `artifact_bundle_zip`
- emits structured events: `content`, `tool_call`, `tool_result`, `ui_component`, `usage`, `done`, `error`.
- multimodal execution status:
  - execution tools implemented: `ocr_extract`, `asr_transcribe`, `tts_synthesize`
  - provider access supports per-request `integration_env` from config center, with process env fallback

## 4. Data Isolation and Consistency

- Session mutations are scoped by `session_id + user_id`.
- Project/source/artifact operations are user-scoped and tenant-scoped.
- Usage logging and billing are transactionally committed in one flow.
  - _Architecture Note: To handle high-concurrency peak loads reliably without saturating DB connection limits, `CommitUsage` is slated for architectural optimization through queue-based asynchronous eventual consistency._
- `billing_logs.request_id` is unique for idempotency.
- Audit/Billing include `skills_used` for traceability.
- Artifacts are linked by `project_id + run_id + role_id + task_id`.

## 5. Role/Task Flow

1. Client fetches role-task catalog from `GET /api/v1/client/use-cases`.
2. User selects role/task and optional extra skills.
3. UI information architecture is scenario-first:
   - left entry: `使用场景`
   - role task panel grouped by profession
   - generic capabilities moved to `更多`
   - supports `添加新技能`

### 5.1 Adaptive Workspace UI Flow (Phase 2.2)

The client implements a three-tier navigation structure to reduce cognitive load:

1.  **Workspaces (Dashboard)**: Grid of project cards + a fixed **Global Draft Chat** entry for non-project history.
2.  **Project Detail**: Intermediate screen for a specific project. Displays linked sources, allows source management, and provides a clear "Start Working" entry point.
3.  **Project Chat**: The core execution environment (Control Plane) where LLM interaction and tool execution happen.

### 5.2 Dynamic Designing: Draft vs formal projects

- **Progressive Disclosure**: Users can start with "Global Draft Chat" without any project setup.
- **Project Promotion**: Temporary/draft interactions can be promoted to formal projects to gain persistence and source management.

## 6. Project Source and Artifact Flow

Each skill is a workflow contract, not only a natural-language instruction:

- `input_schema`: accepted params and source requirements.
- `workflow_steps`: ordered machine-readable steps with step type.
- `step_constraints`: hard constraints (tool required, timeout, min evidence).
- `output_schema`: required artifacts/actions/summary fields.
- `quality_gates`: deterministic checks before success.

Step types:

- `query`: must emit retrieval `tool_call` evidence.
- `generate`: must emit artifact generation evidence.
- `action`: must emit action API/tool evidence.

Success is determined by contract validation, not only model prose quality.

## 6. Project Source and Artifact Flow

1. User manages reusable materials in source library (`user_sources`).
2. User creates/chooses a project (virtual folder).
3. User binds selected library sources into project (`project_sources` composition).
4. During task execution, core passes project sources to engine.
5. Engine can run `source_lookup` for scoped retrieval.
6. Engine can run `artifact_render`/`artifact_bundle_zip` to produce deliverables.
7. Output metadata is stored in `project_artifacts` for audit and retrieval.

This flow is the implementation of the "virtual folder/project as execution unit" requirement:

- scope is project-bounded during retrieval.
- source and output lineage can be tracked by `project_id + run_id`.

## 7. File Entry and Rich Capability UX

- Chat input supports file attachment entry in the client.
- Parsed content is forwarded as message context.
- Engine can emit UI components (charts, artifact cards) for structured rendering.

## 8. Automations Architecture

- `automations`: workflow definition (prompt, skills, schedule metadata).
- `automation_runs`: execution history and accounting facts.
- Current production-ready path: manual `run-now` with full accounting trail.
- Next step: A robust scheduler/worker loop is imperative to realize true timed dispatch and fulfill the automation product promise.

## 9. Configuration Center (New)

Purpose:

- expose operational readiness for workflow-oriented skills.
- provide one panel for tools, integrations, workflow readiness, and profession readiness.
- _Architecture Note: High resilience requires bridging the gap between the Control Plane (showing "configured") and the Execution Plane (actual runtime execution), including robust circuit breaking and fallback strategies when external APIs inevitably spike or fail._

Core data model:

- policy source: `openclaw_tooling_manifest.json`
- runtime panel payload: `config_center_status_panel.template.json`

Panel sections:

- overall summary
- bootstrap checks
- tool readiness
- integration readiness
- workflow readiness (`query/generate/action`)
- profession readiness
- prioritized action queue

Validation loop:

1. load manifest policies
2. collect runtime status and integration checks
3. compute blocking items
4. publish panel payload
5. gate skill release by panel status

Admin interaction path:

1. admin opens `配置中心` in client sidebar
2. toggles integration configured status
3. triggers validation
4. panel recomputes summary/workflow/profession readiness

## 10. Tool Control Center (Product Path)

1. Admin opens `配置中心` and selects tab:
   - `Tools`: enable/disable tools and inspect dependency blockers.
   - `Integrations`: configure encrypted secrets and trigger health checks.
   - `Status`: view aggregated health cards and severity-ranked issues.
2. Gateway loads manifest + tenant state, computes derived statuses, then persists effective state.
3. Every admin mutation (toggle, secret update, check trigger) writes audit entries to `audit_logs`.
4. Frontend only renders secret configured state and masked metadata, never plaintext secret values.
5. Multimodal additions:
   - integrations: `ocr.api`, `asr.api`, `tts.api`
   - tools: `ocr_extract`, `asr_transcribe`, `tts_synthesize`
   - check policy: validate required fields and endpoint format without exposing secrets.
6. Truth model:
   - Control Plane truth: configuration and health status are real and persisted.
   - Execution Plane truth: OCR/ASR/TTS are runtime-bound and can be called in chat execution.
   - Remaining tools should keep explicit warnings when config-ready but runtime-not-bound.
7. v1 consumer boundary:
   - channel-style outbound integrations are intentionally hidden in current public version.
   - enterprise message delivery can be re-opened in later editions.

## 10. Deployment Modes

- Local dev via Docker Compose.
- Shared SaaS deployment for managed multi-user operation.
- Enterprise private deployment is supported by self-hosted stack, with hardening work ongoing.
