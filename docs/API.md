# AIOC API Reference

Base URL: `http://127.0.0.1:8080/api/v1` (recommended)

Compatibility:
- Gateway deployments without `/api/v1` prefix are also supported by client fallback.

## Unified Response

```json
{
  "code": 1,
  "msg": "ok",
  "data": {},
  "trace_id": "uuid"
}
```

## Auth

### `POST /auth/login`
- input: `email`, `password`
- output: `access_token`, `refresh_token`, `user`

### `POST /auth/refresh`
- input: `refresh_token`
- note: only refresh token type is accepted.

## Client Metadata

### `GET /client/capabilities`
- returns feature flags by plan.

### `GET /client/skills`
- returns skill catalog for UI capability selection.
- now sourced from the same recipe config as `use-cases`:
  - default: `server/gateway-go/config/usecases.json`
  - override by env: `AIOC_USE_CASES_FILE`

### `GET /client/use-cases`
- returns role-based task catalog (`roles -> tasks`) for scenario-first UX.
- now backed by recipe config file:
  - default: `server/gateway-go/config/usecases.json`
  - override by env: `AIOC_USE_CASES_FILE`

## Chat

### `POST /chat/stream` (SSE)

Request body:
```json
{
  "session_id": "optional-uuid",
  "messages": [{ "role": "user", "content": "..." }],
  "mode": "economy",
  "skills": ["shell_ops", "file_analysis"],
  "role_id": "student",
  "task_id": "student.knowledge_summary",
  "project_id": "optional-project-uuid"
}
```

SSE events:
- `content`
- `tool_call`
- `tool_result`
- `ui_component`
- `done`
- `error`

## Sessions

### `GET /sessions`
- list current user sessions.

### `GET /sessions/:id`
- get one session with persisted message history.

### `POST /sessions`
- create session.

### `DELETE /sessions/:id`
- delete session.

## Projects

### `GET /projects`
- list user projects (virtual folders).

### `POST /projects`
- create project.
- body: `name`, `description`.

### `GET /projects/:id/sources`
- list local sources in project.

### `POST /projects/:id/sources`
- add one source into project.
- body:
  - bind from library: `source_id` (+ `source_type`, `name` for compatibility)
  - or direct add: `source_type(text|file|image|audio|link)`, `name`, `content_text`, `file_path`, `link_url`, `metadata`.

### `DELETE /projects/:id/sources/:source_id`
- remove one source binding from project composition.

## Source Library

### `GET /sources`
- list all user library sources.

### `POST /sources`
- create one source in user library.
- body: `source_type(text|file|image|audio|link)`, `name`, `content_text`, `file_path`, `link_url`, `metadata`.

### `PUT /sources/:id`
- update one source in user library.

### `DELETE /sources/:id`
- delete one source from user library.

## Billing

### `GET /billing/summary?period=YYYY-MM`
- monthly usage and cost totals.

### `POST /billing/verify_receipt`
- IAP receipt verification path (integration in progress).

## Automations

### `GET /automations`
- list automations for current user.

### `POST /automations`
- create automation.
- body: `name`, `prompt`, `skills[]`, `schedule_kind`, `interval_hours`, `timezone`, `run_immediately`.

### `PATCH /automations/:id/status`
- set status: `active` or `paused`.

### `DELETE /automations/:id`
- soft-delete automation.

### `POST /automations/:id/run`
- execute automation immediately.
- response includes run result summary (`tokens`, `cost`, `request_id`, preview).

### `GET /automations/:id/runs`
- list recent run history for the automation.

## Headers

- `Authorization: Bearer <token>` for protected routes.
- `X-Client-ID` and `X-Client-Version` recommended for client policy checks.
- `X-Trace-ID` optional; server generates if absent.
