# Engine Protocol (SPI)

Defines the contract between `core-go` and execution engines (current engine: OpenClaw).

## Endpoint

- `POST /execute` (SSE response)
- `GET /health`

## Request: `AgentRequest`

```json
{
  "session_id": "uuid",
  "messages": [{ "role": "user", "content": "..." }],
  "config": {
    "model_name": "deepseek-chat",
    "base_url": "https://api.deepseek.com/v1",
    "api_key": "sk-***"
  },
  "skills": ["shell_ops", "data_viz"],
  "allowed_tools": ["execute_command", "request_data_chart"],
  "plan_level": "pro",
  "mode": "economy",
  "trace_id": "trace-uuid",
  "tenant_id": "tenant-uuid",
  "user_id": "user-uuid",
  "client_id": "client-uuid"
}
```

## SSE Event Types

- `content`: streamed model text delta.
- `tool_call`: tool name and args requested by engine.
- `tool_result`: normalized tool output summary.
- `ui_component`: render instruction for client components.
- `usage`: token usage counters.
- `done`: terminal event with completion metadata.
- `error`: terminal failure.

## `ui_component` Payload

```json
{
  "component": "data_chart",
  "args": {
    "title": "Weekly Cost",
    "x": ["Mon", "Tue", "Wed"],
    "series": [{ "name": "cost", "data": [1.2, 1.8, 1.4] }]
  }
}
```

## `done` Payload (recommended fields)

```json
{
  "model": "deepseek-chat",
  "tokens_in": 100,
  "tokens_out": 220,
  "cost": "0.000123",
  "request_id": "uuid",
  "trace_id": "trace-uuid"
}
```

## Security and Runtime Constraints

- Engine must stay stateless; context is request-scoped.
- Engine must not own billing/session writes.
- Tool execution must respect `allowed_tools` from core.
- Command execution must enforce policy checks before execution.
- API keys must come from request context, not static engine env.
