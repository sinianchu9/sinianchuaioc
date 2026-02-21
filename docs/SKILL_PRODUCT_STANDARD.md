# AIOC Skills 产品标准（中文）

Last updated: 2026-02-21

## 1. 目的

本标准用于把 skills 从“提示词任务”升级为“可执行、可校验、可审计”的工作流合同（workflow contract）。

目标：
- 执行路径可确定
- 能力边界可验证
- 产物与动作有证据
- 失败原因可定位

## 2. Skills 基础依赖（19 个已注册能力 + 使用场景）

说明：
- 下表为当前 manifest 已注册能力，来源：`server/gateway-go/config/tools.manifest.yaml`
- skills 可执行边界 = 已注册能力集合 ∩ 当前状态为 `OK` 且已启用

| 能力 ID | 分类 | 依赖 | 典型使用场景 |
|---|---|---|---|
| `openclaw.fs` | 系统核心 | 无 | 读写资料、保存中间结果、产物归档 |
| `openclaw.runtime` | 系统核心 | 无 | 工作流编排、步骤执行、上下文管理 |
| `openclaw.ui.browser` | 系统内部 | 本机 `playwright` | 网页自动化采集、表单操作、页面截图 |
| `openclaw.web_fetch` | 外部能力 | `search.brave` | 联网检索、网页正文抓取 |
| `aioc.artifact_render` | 外部能力 | `llm.openai` | 生成报告/文档/表格等结构化产物 |
| `aioc.task.create` | 外部能力 | `task.api` | 向外部任务系统下发任务 |
| `ocr_extract` | 外部能力 | `ocr.api` | 图片转文字、票据/截图识别 |
| `asr_transcribe` | 外部能力 | `asr.api` | 语音转文字、会议录音转写 |
| `tts_synthesize` | 外部能力 | `tts.api` | 文字转语音播报 |
| `openclaw.template.apply` | 系统内部 | 无 | 按模板填充变量、统一输出结构 |
| `openclaw.output.validate` | 系统内部 | 无 | 校验 JSON/字段完整性/格式正确性 |
| `openclaw.policy.check` | 系统内部 | 无 | 发布前策略校验、敏感动作门禁 |
| `openclaw.schedule.create` | 系统内部 | 无 | 创建定时任务（日报/周报/巡检） |
| `openclaw.trigger.watch` | 系统内部 | 无 | 监听事件触发自动执行 |
| `openclaw.review.request` | 系统内部 | 无 | 人工审批（提交审核、等待通过） |
| `openclaw.execution.pause` | 系统内部 | 无 | 暂停/恢复执行链路 |
| `openclaw.audit.log` | 系统内部 | 无 | 写入审计日志与追踪证据 |
| `openclaw.quota.check` | 系统内部 | 无 | 执行前配额和成本检查 |
| `openclaw.secret.resolve` | 系统内部 | 无 | 运行时读取密钥并注入工具调用 |

补充：
- 外部连接当前共 6 项：`llm.openai`、`search.brave`、`task.api`、`ocr.api`、`asr.api`、`tts.api`
- 外部连接缺失时，对应能力会被标记阻塞，不应发布依赖该能力的 skill

## 3. Skills 标准（必须满足）

每个 skill 必须具备以下合同字段。

1. 标识与范围
- `skill_id`、`version`、`owner`、`domain`、`applicable_roles`

2. 输入合同
- `required_params`
- `optional_params`（含默认值）
- `required_source_types`（`text/file/image/audio/link`）
- `min_sources`

3. 工作流步骤合同
- `workflow_steps[]` 按顺序定义
- 每步必须声明：`type`、`objective`、`required_tools`、`allowed_tools`
- 步骤类型建议：`query | generate | action | decide | automate | review | governance`

4. 强约束
- 关键步骤禁止 best effort，必须可验证
- 每步要定义 `timeout_sec`、`retry_policy`、`must_emit_tool_call`
- 必须有预算约束（如 `max_cost`/`max_tokens`）

5. 输出合同
- 明确 `required_fields`
- 有产物的步骤要定义 `required_artifacts`（格式/命名/位置）
- 有动作的步骤要定义 `required_action_receipts`

6. 质量门禁
- `quality_gates[]` 必须可机器判定
- 门禁不通过必须失败并返回明确错误码

7. 审计证据
- 保存步骤级 `tool_call`、`tool_result`
- 绑定 `project_id`、`source_id`、`run_id`、`artifact_id`、`action_id`

## 4. 分步骤最低通过规则

1. `query`
- 至少 1 次检索类工具调用证据（如 `openclaw.web_fetch`）
- 输出必须带来源引用

2. `generate`
- 至少 1 个真实产物（不是“已生成”的文本声明）
- 产物必须可定位（路径/URL/元信息）

3. `action`
- 必须有外部动作回执（如任务 ID）
- 无回执视为失败

4. `decide/review/governance`
- 必须有策略/审批/审计证据
- 审批未通过不得进入后续高风险步骤

## 5. Skill 合同示例（标准模板）

```json
{
  "skill_id": "teacher.lesson_delivery.v1",
  "version": "1.0.0",
  "owner": "edu-product",
  "domain": "education",
  "applicable_roles": ["teacher"],
  "input_schema": {
    "required_params": ["project_id", "subject", "grade_level"],
    "optional_params": { "duration_minutes": 45 },
    "required_source_types": ["text", "file", "image"],
    "min_sources": 1
  },
  "workflow_steps": [
    {
      "step_id": "s1_retrieve",
      "type": "query",
      "required_tools": ["openclaw.fs", "openclaw.web_fetch"],
      "allowed_tools": ["openclaw.fs", "openclaw.web_fetch"],
      "constraints": { "must_emit_tool_call": true, "timeout_sec": 30 }
    },
    {
      "step_id": "s2_generate",
      "type": "generate",
      "required_tools": ["openclaw.template.apply", "aioc.artifact_render", "openclaw.output.validate"],
      "allowed_tools": ["openclaw.template.apply", "aioc.artifact_render", "openclaw.output.validate"],
      "constraints": {
        "must_emit_tool_call": true,
        "required_artifacts": [
          { "name": "lesson_plan", "format": "docx" },
          { "name": "class_slides", "format": "pdf" }
        ],
        "timeout_sec": 90
      }
    },
    {
      "step_id": "s3_action",
      "type": "action",
      "required_tools": ["aioc.task.create"],
      "allowed_tools": ["aioc.task.create"],
      "constraints": {
        "must_emit_tool_call": true,
        "required_action_receipts": ["task_id"],
        "timeout_sec": 20
      }
    }
  ],
  "quality_gates": [
    { "gate_id": "g1", "condition": "query steps have retrieval evidence" },
    { "gate_id": "g2", "condition": "artifacts include docx and pdf" },
    { "gate_id": "g3", "condition": "action has task_id receipt" }
  ],
  "failure_codes": [
    "ERR_INPUT_SOURCE_INSUFFICIENT",
    "ERR_MISSING_REQUIRED_TOOL_CALL",
    "ERR_ARTIFACT_NOT_GENERATED",
    "ERR_ACTION_NOT_CONFIRMED"
  ]
}
```

## 6. 展示案例（能力 + 标准联合落地）

案例：`teacher.lesson_delivery.v1`（老师备课并下发任务）

1. 目标
- 输入项目资料，输出教案产物，并自动创建教学执行任务

2. 使用能力（示例）
- 系统内部：`openclaw.fs`、`openclaw.runtime`、`openclaw.template.apply`、`openclaw.output.validate`、`openclaw.policy.check`、`openclaw.audit.log`、`openclaw.quota.check`、`openclaw.secret.resolve`
- 外部能力：`openclaw.web_fetch`、`aioc.artifact_render`、`aioc.task.create`、`ocr_extract`

3. 步骤
- `s0_precheck`：`openclaw.quota.check` + `openclaw.policy.check`
- `s1_collect`：`openclaw.fs` + `ocr_extract` + `openclaw.web_fetch`
- `s2_render`：`openclaw.template.apply` + `aioc.artifact_render`
- `s3_validate`：`openclaw.output.validate`
- `s4_publish`：`aioc.task.create`
- `s5_audit`：`openclaw.audit.log`

4. 成功判定
- 产物齐全（docx/pdf）
- 任务系统返回 `task_id`
- 审计记录完整（含工具调用证据）

5. 外行可读的失败排查
- 若 `openclaw.web_fetch` 失败：优先检查 `search.brave` 是否已配置
- 若 `aioc.artifact_render` 失败：检查 `llm.openai` 密钥和连通性
- 若 `aioc.task.create` 失败：检查 `task.api` 地址与令牌
- 若系统类步骤失败：看配置中心“系统工具”页是否 `disabled/error`

## 7. 上线门禁（必须同时满足）

- 该 skill 所需能力全部已注册
- 所需能力状态为 `OK` 且已启用
- 所需外部连接字段完整并校验通过
- 工作流质量门禁全部通过
- 无 `p0` 阻塞项

## 8. 与配置中心的对应关系

- 总览：看“系统工具/外部连接/阻塞项”是否满足 skill 依赖
- 系统工具：排查本机依赖和运行时异常
- 外部连接：补齐 API Key/URL/OAuth 字段
- 状态中心：确认 `ERROR` 清零后再发布 skill

## 9. 迁移建议

1. 保留原 `usecases.json` 作为前端分类入口
2. 为高频 skill 新增 workflow contract（JSON）
3. 在 runtime 中按 `role + task + skill_id` 加载合同并校验
4. 先迁移高频 10 个职业 skill，再覆盖长尾
