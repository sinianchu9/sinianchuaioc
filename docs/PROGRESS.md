# AIOC Engineering Progress

Last updated: 2026-02-19

## Current Stage

Project status is **late prototype / early production hardening**.
Core direction has moved from pure Skills picker to **Role/Task scenario execution** with project-scoped sources and artifact outputs.
Current gap: profession skills are still mostly **task-level placeholders** and not yet **workflow-oriented production skills**.

## Completed (Shipped)

### Phase 2 and Core UX
- Multi-session chat with SSE streaming.
- Session history persistence (`sessions.messages`) and session detail API.
- Stop-generation support for stream interruption.
- File entry from client input (local file selection + guarded payload handling).
- UI component rendering path (chart component support).

### Skills and Use Cases
- Skills catalog endpoint: `GET /api/v1/client/skills`.
- Role-task catalog endpoint: `GET /api/v1/client/use-cases`.
- Use-case catalog is now config-driven from `server/gateway-go/config/usecases.json` (env override: `AIOC_USE_CASES_FILE`).
- Skills catalog is now loaded from the same config source as use-cases (single source of truth).
- Client supports scenario-first screen (role tabs + task chips + generic skills + more).
- Client role/task panel now reads backend `use-cases` directly (local hardcoded matcher removed).
- Chat requests now carry `skills[] + role_id + task_id + project_id`.
- Core injects role/task/project execution context and computes allowed tools by `plan + skills`.
- Engine enforces allowed tool subset and emits tool timeline events.
- Client API now supports `AIOC_API_BASE_URL` at startup and 404 fallback between `/api/v1` and non-versioned gateway routes.
- Scenario loader now falls back to skills-derived use-cases when `use-cases` endpoint is empty/unavailable, preventing empty task panel.
- Tooling prerequisite baseline published:
  - `server/gateway-go/config/openclaw_tooling_manifest.json`
  - includes tool bootstrap list, admin integrations, dependency map, and bootstrap checks.
- Config center status panel baseline published:
  - `server/gateway-go/config/config_center_status_panel.template.json`
  - `docs/CONFIG_CENTER_STATUS_PANEL_SPEC.md`
  - `docs/CONFIG_CENTER_UI_FIELD_MAPPING.md`
- Config center admin interactive UI delivered:
  - Gateway admin APIs:
    - `GET /api/v1/admin/config-center/manifest`
    - `GET /api/v1/admin/config-center/status`
    - `POST /api/v1/admin/config-center/validate`
    - `PATCH /api/v1/admin/config-center/integrations/:id`
  - Flutter admin screen:
    - sidebar entry `配置中心` (admin role only)
    - interactive integration toggles
    - manual validation trigger and live status refresh
- Tool & Integration Control Center delivered (new production path):
  - Manifest parser source:
    - `server/gateway-go/config/tools.manifest.yaml`
  - DB migration:
    - `server/migrations/006_tool_control_center.sql`
  - New tenant-scoped tables:
    - `integrations`
    - `integration_secrets` (AES-GCM encrypted secret storage)
    - `tool_status`
  - New admin APIs:
    - `GET /api/v1/admin/tools`
    - `GET /api/v1/admin/tools/:id`
    - `POST /api/v1/admin/tools/:id/toggle`
    - `GET /api/v1/admin/integrations`
    - `GET /api/v1/admin/integrations/:id`
    - `POST /api/v1/admin/integrations/:id/secret`
    - `POST /api/v1/admin/integrations/:id/check`
    - `GET /api/v1/admin/status/summary`
  - Status model:
    - `OK / WARN / ERROR / DISABLED / MISSING_CREDENTIALS / MISCONFIGURED`
  - Health-check caching:
    - per-tenant/integration 60s cache for repeated check calls
  - Admin UI upgraded to 3 panes:
    - `Tools / Integrations / Status`
  - v1 consumer scope adjustment:
    - `channel.*` integrations hidden from active config center manifest
    - message/channel delivery kept out of current public version surface
  - Multimodal capability registry expanded:
    - tools: `aioc.ocr.extract`, `aioc.asr.transcribe`, `aioc.tts.synthesize`
    - integrations: `ocr.api`, `asr.api`, `tts.api`
    - check types: `ocr_api`, `asr_api`, `tts_api`
  - Current delivery stage:
    - configuration + health-check readiness completed in Config Center
    - OCR/ASR/TTS runtime tool wiring completed in engine/core:
      - tools: `ocr_extract`, `asr_transcribe`, `tts_synthesize`
      - allowed tools in core are enabled by default for v1 multimodal usage
  - Legacy compatibility:
    - old `config-center` manifest now also includes OCR/ASR/TTS entries
    - frontend falls back to legacy endpoints for configure/check actions when new endpoints are unavailable

### Project Sources and Artifacts
- Project APIs:
  - `GET /api/v1/projects`
  - `POST /api/v1/projects`
  - `GET /api/v1/projects/:id/sources`
  - `POST /api/v1/projects/:id/sources`
- Source library APIs:
  - `GET /api/v1/sources`
  - `POST /api/v1/sources`
- DB migration added:
  - `projects`
  - `project_sources`
  - `project_artifacts`
- New DB migration:
  - `user_sources` (global per-user source library)
- Core loads `project_sources` and passes them to engine request payload.
- Engine `source_lookup` now prefers request-scoped project sources.
- New engine tools:
  - `artifact_render`
  - `artifact_bundle_zip`
  - `source_lookup`
- `artifact_render` now uses Python renderer script:
  - real `docx/xlsx/pdf` generation when dependencies exist
  - fallback JSON payload output when dependency missing
- Engine emits artifact UI components (`artifact_file`, `artifact_bundle`).
- Client can render artifact cards in chat bubbles.
- Client scenario page supports project creation + source import UX (`text/file/image/audio/link`) with project-scoped source list.
- Sidebar now includes dedicated `资料` and `项目` pages:
  - `资料`: manage personal source library.
  - `项目`: compose a project from library sources, then open project chat.
- Core parses artifact tool results and persists metadata into `project_artifacts`.

### Security and Consistency Hardening (P0)
- Session update isolation with `session_id + user_id` conditions.
- Billing idempotency:
  - `billing_logs.request_id` unique constraint.
  - synchronous transactional usage commit path (`CommitUsage`).
- JWT hardening:
  - token type claim (`access` / `refresh`).
  - refresh endpoint rejects access token misuse.
- Client version check moved from lexical string compare to semver compare.
- Cost circuit breaker wired to real SSE `done.cost`.
- Tool execution hardening in engine:
  - cross-mode blacklist/whitelist enforcement.
  - stricter command validation and reduced shell-injection surface.

### Automations
- Automation CRUD endpoints.
- Run APIs:
  - `POST /api/v1/automations/:id/run`
  - `GET /api/v1/automations/:id/runs`
- Run execution writes `automation_runs` with status, tokens, cost, request_id, and preview.
- Client automation screen supports create/pause/resume/delete/run-now/runs-history.

## Verification Snapshot

- `go test ./...` passed for `server/gateway-go`.
- `go test ./...` passed for `server/core-go`.
- `npm run build` passed for `server/engine-openclaw`.
- `flutter analyze` passed for `client/flutter_app`.
- Local renderer smoke test passed for:
  - `docx`
  - `xlsx`
  - `pdf`

## Readme3 Alignment (Current Focus)

The current delivery is explicitly converged to three priorities from `readme3-important`:

1. Role-packaged skills (not free-form skill picking):
- Left navigation renamed to `使用场景`.
- Scenario panel now supports role-first task selection (student/teacher/doctor/lawyer/accountant/support/ecommerce).
- Generic capabilities are grouped into `更多`, with `添加新技能` entry.

2. Local source organization by project (virtual folder):
- `projects` + `project_sources` schema and APIs are live.
- Source types supported in schema/API: `text | file | image | audio | link`.
- Chat execution can bind `project_id` so only current project sources are used as context.

3. Production outputs (deliverables, not only chat text):
- Engine supports `artifact_render` + `artifact_bundle_zip`.
- Supported generation baseline: `docx/xlsx/pdf/md/csv/json/txt` (+ zip bundle).
- Core persists output metadata into `project_artifacts`.
- Client renders downloadable artifact cards in chat.

## Remaining High-Priority Work

- Run DB migration `004_role_project_output.sql` in all deployed environments.
- Add role recipe configuration source (DB/config files) to replace hardcoded role-task catalog.
- Complete first production recipe set:
  - student/teacher/doctor/lawyer/accountant/support/ecommerce
  - each role with explicit task contracts and default skill/tool policy.
- Add artifact retrieval/download APIs from `project_artifacts` metadata.
- Add project artifact list UI and run-level output traceability view.
- Scheduler worker for real timed automation triggers (currently run-now/manual path is ready).
- End-to-end migration validation on upgrade paths (older DBs to latest schema).
- More negative/security tests: cross-user access attempts, retry/error accounting paths.
- Production observability baseline: metrics, tracing dashboards, alert rules.

## Skills Productization Program (New)

This program upgrades AIOC skills from task prompts to production workflows.

### Scope
- Shift from **Task-Driven** to **Workflow-Oriented** skills.
- Add strict contracts for `query`, `generate`, and `action` steps.
- Add machine-checkable constraints (not only prompt wording).

### Product-Level Definition of Done
- Each profession skill must define:
  - input contract
  - workflow steps
  - tool requirements
  - output contract
  - quality gates
  - audit trace requirements
- Query workflows must produce tool calls to at least one configured retrieval tool.
- Generation workflows must produce at least one artifact output (`docx/xlsx/pdf/...`) via tool.
- Action workflows must call action interfaces (notification/task creation/push), not text-only simulation.

### Tracking Milestones
- M1: publish skill standard and templates (`docs/SKILL_PRODUCT_STANDARD.md`).
- M2: migrate top 10 high-frequency profession skills to workflow contracts.
- M3: add runtime validators for required tool-call and required artifact/action outputs.
- M4: enable quality scoring and failure taxonomy in run logs for each workflow step.
- M5: ship Config Center status panel API + UI backed by tooling manifest and runtime checks.
