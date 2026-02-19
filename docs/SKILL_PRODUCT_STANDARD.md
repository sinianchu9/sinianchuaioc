# AIOC Product-Grade Skill Standard

Last updated: 2026-02-19

## 1. Goal

This standard upgrades profession skills from **task prompts** to **workflow contracts**.

Target:
- deterministic execution path
- enforceable constraints
- auditable tool evidence
- production outputs and actions

## 2. Design Shift

From:
- Task-Driven: "tell model what to do"

To:
- Workflow-Oriented: "define steps, constraints, required tools, required outputs, required evidence"

## 3. Product-Grade Skill Must-Haves

Each profession skill must include all items below.

1. Identity and scope:
- `skill_id`, `version`, `owner`, `domain`, `applicable_roles`

2. Input contract:
- required params
- optional params with defaults
- accepted source types (`text/file/image/audio/link`)
- required source minimums (for example at least 1 source)

3. Workflow graph:
- ordered `workflow_steps`
- each step has explicit type: `query | generate | action | review`
- each step defines allowed tools and forbidden tools

4. Hard constraints:
- no "best effort" for critical steps
- required tool calls by step type
- step timeout / retry policy
- max token/cost budget

5. Output contract:
- required output fields
- required artifact formats for generate workflows (`docx/xlsx/pdf/...`)
- required action receipts for action workflows (`notification_id/task_id/...`)

6. Quality gates:
- objective checks (schema valid, citations count, artifact generated, action ack)
- fail with explicit error code when gate not met

7. Audit evidence:
- step-level `tool_call` and `tool_result`
- source lineage (`source_id`, `project_id`)
- artifact lineage (`artifact_id`, `run_id`)
- action lineage (`action_id`, endpoint, response code)

## 4. Mandatory Rules by Step Type

### 4.1 Query Steps

Rule:
- must produce at least one retrieval tool call evidence.

Valid evidence:
- `tool_call` with tool in retrieval class: `source_lookup`, db query tool, web fetch tool, kb retrieval tool.

Forbidden completion:
- pure text answer with no retrieval tool evidence.

Minimum output:
- normalized findings list with source references.

### 4.2 Generate Steps

Rule:
- must produce at least one artifact output through tool execution.

Valid evidence:
- `tool_call` to `artifact_render` or equivalent generator.
- artifact metadata persisted (format, path/url, checksum/size).

Forbidden completion:
- only plain text saying "report generated".

Minimum output:
- artifact list with `type`, `format`, `name`, `location`.

### 4.3 Action Steps

Rule:
- must call action interface/tool and return ack.

Valid evidence:
- `tool_call` to notification/task/push API tools.
- action receipt with id/status/target/time.

Forbidden completion:
- plain text "已发送通知" without API/tool evidence.

Minimum output:
- action receipts array.

## 5. Skill Contract Format (Recommended JSON)

```json
{
  "skill_id": "teacher.lesson_prep.v1",
  "name": "备课工作流",
  "version": "1.0.0",
  "owner": "edu-product",
  "domain": "education",
  "applicable_roles": ["teacher"],
  "intent": "基于项目资料生成可执行教案并推送任务",
  "input_schema": {
    "required_params": ["project_id", "grade_level", "subject"],
    "optional_params": {
      "duration_minutes": 45
    },
    "required_source_types": ["text", "file", "link"],
    "min_sources": 1
  },
  "workflow_steps": [
    {
      "step_id": "s1_collect",
      "type": "query",
      "objective": "检索项目内资料并提取教学要点",
      "required_tools": ["source_lookup"],
      "allowed_tools": ["source_lookup"],
      "forbidden_tools": [],
      "constraints": {
        "must_emit_tool_call": true,
        "min_tool_calls": 1,
        "timeout_sec": 20
      },
      "output_schema": {
        "required_fields": ["key_points", "references"]
      }
    },
    {
      "step_id": "s2_generate_lesson_plan",
      "type": "generate",
      "objective": "生成教案文档与课堂流程表",
      "required_tools": ["artifact_render"],
      "allowed_tools": ["artifact_render"],
      "constraints": {
        "must_emit_tool_call": true,
        "required_artifacts": [
          { "name": "lesson_plan", "format": "docx" },
          { "name": "class_flow", "format": "xlsx" }
        ],
        "timeout_sec": 60
      }
    },
    {
      "step_id": "s3_notify",
      "type": "action",
      "objective": "向教学群发送教案通知并创建任务",
      "required_tools": ["notify_send", "task_create"],
      "allowed_tools": ["notify_send", "task_create"],
      "constraints": {
        "must_emit_tool_call": true,
        "required_action_receipts": ["notification_id", "task_id"],
        "timeout_sec": 15
      }
    }
  ],
  "quality_gates": [
    {
      "gate_id": "g1",
      "condition": "query step has >=1 retrieval tool_call"
    },
    {
      "gate_id": "g2",
      "condition": "artifact outputs include required formats"
    },
    {
      "gate_id": "g3",
      "condition": "action receipts include notification_id and task_id"
    }
  ],
  "output_contract": {
    "summary_required": true,
    "artifacts_required": true,
    "actions_required": true
  },
  "failure_codes": [
    "ERR_MISSING_REQUIRED_TOOL_CALL",
    "ERR_ARTIFACT_NOT_GENERATED",
    "ERR_ACTION_NOT_CONFIRMED",
    "ERR_INPUT_SOURCE_INSUFFICIENT"
  ]
}
```

## 6. Tool Interface Types (Required)

To support action workflows, define tools by type:

1. Retrieval tools:
- `source_lookup`
- `kb_search`
- `db_query`
- `web_fetch`

2. Generation tools:
- `artifact_render`
- `artifact_bundle_zip`

3. Action tools:
- `notify_send`
- `task_create`
- `ticket_create`
- `webhook_post`

4. Multimodal tools:
- `ocr_extract` (image -> text)
- `asr_transcribe` (audio -> text)
- `tts_synthesize` (text -> audio)

Version note (v1 consumer):
- channel/action delivery connectors are intentionally reduced in current public surface.
- multimodal OCR/ASR/TTS is prioritized for current release track.

Each tool must define:
- `name`
- `request_schema`
- `response_schema`
- `error_codes`
- `idempotency_key` behavior (for action tools)

Multimodal additional constraints:
- OCR/ASR outputs must include language/confidence fields when provided by provider.
- TTS outputs must include artifact metadata (`format`, `duration`, `location`).
- Raw media input/output path must be traceable to `source_id/project_id/run_id`.

## 7. Runtime Validation Rules

Execution is successful only when all apply:
- all required steps executed in order
- all required tool calls present
- all required artifacts/actions confirmed
- quality gates pass

Otherwise mark run as failed with precise failure code and step id.

## 8. Profession Skill Authoring Checklist

For each new profession skill:
- define one concrete business outcome
- split into `query -> generate -> action` where needed
- bind each step to concrete tools
- specify hard constraints and minimum evidence
- define machine-readable output contract
- add failure codes and fallback policy
- add sample input and expected outputs

## 9. Migration Plan for Existing Skills

1. Keep existing `usecases.json` for UI taxonomy.
2. Add workflow contracts in a dedicated catalog (for example `skill_contracts/*.json`).
3. In core runtime, map selected task/skill id to workflow contract.
4. Add contract validator before emitting final success.
5. Gradually migrate placeholders to full workflow contracts by profession priority.

## 10. Tooling Prerequisite Manifest (Mandatory Input)

Before building or enabling any profession skill, read:
- `server/gateway-go/config/openclaw_tooling_manifest.json`

How to use:
- System initialization reads `system_init_install_tools` to know which tools must be installed/enabled.
- Admin setup reads `admin_provided_api_integrations` to know which external APIs/credentials must be provided.
- Skill contract validation reads `workflow_enforcement_rules` to enforce query/generate/action evidence requirements.

Skill authoring rule:
- A skill cannot be marked "production-ready" if required tools in the manifest are missing or admin integrations are not configured.
