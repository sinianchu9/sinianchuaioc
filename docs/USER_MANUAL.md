# AIOC 操作手册（职业场景版）

Last updated: 2026-02-21

## 1. 登录与入口

1. 登录后进入系统主界面。
2. 左侧核心入口：`聊天`、`使用场景`、`资料`、`项目`。

## 2. 使用场景（技能执行）

1. 打开 `使用场景`。
2. 选择职业与任务（如学生/老师/律师等）。
3. 选择项目（重要）。
4. 进入 `聊天` 发送任务指令，系统会按 `role + task + project` 执行。
5. 技能加载方式（新）：
   - 在聊天输入框输入 `/`，会弹出 skills 下拉列表。
   - 点击下拉项即可加入当前会话技能。
   - 输入框上方会显示“已选技能”标签，点击 `x` 可随时取消。
   - 聊天顶部旧的技能展示/选择方式已移除。

## 3. 资料库（全量资料管理）

1. 打开左侧 `资料` 页面。
2. 点击 `新增资料`，支持类型：`文本 / 文件 / 图片 / 音频 / 链接`。
3. 支持对资料进行：
   - 搜索
   - 编辑
   - 删除
4. 资料库是你的“全量资产”，不绑定单个项目。

## 4. 项目（资料组合）

1. 打开左侧 `项目` 页面。
2. 新建或选择项目。
3. 从资料库中点击 `加入项目`，把资料组合到当前项目。
4. 在 `项目已选资料` 区域可：
   - 搜索
   - 移除资料（仅移除项目绑定，不删资料库原件）
5. 点击 `打开项目对话`，直接进入聊天并使用该项目资料源。

## 5. 推荐流程（NotebookLM 风格）

1. 先在 `资料` 页录入全部资料源。
2. 在 `项目` 页按任务主题组合资料（如错题组合、知识点组合）。
   _注：未来将支持在上传资料时提供“一键基于此资料创建项目”的快捷交互，进一步降低操作成本。_
3. 打开项目对话。
4. 在 `使用场景` 选技能任务并执行。
5. 下载输出结果（docx/xlsx/pdf/zip 等）。

## 6. 常见问题与异常处理

1. 添加资料后看不到：
   - 点击 `资料` 页 `刷新`。
   - 检查是否有错误提示条。
2. 项目里不能操作：
   - 先选择一个项目。
   - 确保资料库里有可加入条目。
3. 执行中遇到报错（如“生成失败”、“配额不足”、“网络异常”）：
   - 系统底层的详细错误代码将被转换为友好的操作建议显示在聊天界面中。
   - 请根据建议的“下一步”重试或联系管理员补充配置。
4. Flutter VM Service 报错（`Invalid WebSocket upgrade request`）：
   - 使用固定端口启动：`flutter run --host-vmservice-port 8181`
   - Web 可加：`flutter run -d chrome --web-port 7357`
5. 创建项目时报 `Invalid JSON response status 404`：
   - 启动时显式指定网关地址：
     - `flutter run --dart-define=AIOC_API_BASE_URL=http://127.0.0.1:8080/api/v1`
   - 如果网关未带 `/api/v1` 前缀，也可用：
     - `flutter run --dart-define=AIOC_API_BASE_URL=http://127.0.0.1:8080`

## 7. 管理员配置

1. 职业/任务/技能配置：`server/gateway-go/config/usecases.json`
2. 配置路径环境变量：`AIOC_USE_CASES_FILE=/path/to/usecases.json`
3. 建议先执行数据库迁移：
   - `004_role_project_output.sql`
   - `005_user_sources_library.sql`

## 8. 一键修复与验收（打包脚本）

1. 脚本位置：`scripts/fix-404.ps1`
2. 默认执行（重建服务 + 迁移 + 路由检查 + 登录后技能/场景/项目/资料验收）：
   - `powershell -ExecutionPolicy Bypass -File .\scripts\fix-404.ps1`
3. 跳过登录验收（仅做基础修复）：
   - `powershell -ExecutionPolicy Bypass -File .\scripts\fix-404.ps1 -SkipSmokeCheck`
4. 自定义测试账号：
   - `powershell -ExecutionPolicy Bypass -File .\scripts\fix-404.ps1 -SmokeEmail user@aioc.internal -SmokePassword 123456`
5. 成功后按脚本输出启动 Flutter：
   - `flutter run --host-vmservice-port 8181 --dart-define=AIOC_API_BASE_URL=http://127.0.0.1:8080/api/v1`

## 8.1 工具配置中心初始化脚本

1. 脚本位置：`scripts/init-tool-control-center.ps1`
2. 功能：
   - 生成并写入 `MASTER_KEY` 到 `.env.tool-control-center.local`
   - 生成 compose override 注入 gateway 的 `MASTER_KEY`
   - 启动/重建服务并执行 `006_tool_control_center.sql`
   - 校验新版 admin 路由不是 404
3. 执行：
   - `powershell -ExecutionPolicy Bypass -File .\scripts\init-tool-control-center.ps1`
4. 仅迁移与检查（不重启服务）：
   - `powershell -ExecutionPolicy Bypass -File .\scripts\init-tool-control-center.ps1 -SkipServiceRestart`

## 9. 配置中心状态面板（管理员）

1. 面板目标：
   - 看清系统工具是否可用。
   - 看清管理员外部 API 是否配置完整。
   - 看清 `query/generate/action` 三类工作流是否可发布。
2. 配置来源：
   - 工具策略与依赖：`server/gateway-go/config/openclaw_tooling_manifest.json`
   - 状态面板数据模板：`server/gateway-go/config/config_center_status_panel.template.json`
3. 面板规格与字段映射：
   - 面板规格：`docs/CONFIG_CENTER_STATUS_PANEL_SPEC.md`
   - 前端字段映射：`docs/CONFIG_CENTER_UI_FIELD_MAPPING.md`
4. 使用方式（当前文档阶段）：
   - 先填写/生成状态模板 JSON。
   - 按 `overall_status` 与 `actions` 判断阻断项。
   - 优先处理 `p0` 动作项（如 LLM、`kb_search`、`notify_send`、`task_create`）。
5. 发布门禁：
   - `workflow_readiness` 全部 `ok`。
   - 目标职业 `profession_readiness` 为 `ok`。
   - 无未完成 `p0` 动作。

## 10. 配置中心界面操作（已接入系统）

1. 仅管理员角色可见左侧入口：`配置中心`。
2. 页面支持：
   - 刷新状态（读取最新状态面板）
   - 执行校验（触发后端重算）
   - 直接切换各集成项 `configured` 状态
3. 后端接口：
   - `GET /api/v1/admin/config-center/status`
   - `POST /api/v1/admin/config-center/validate`
   - `PATCH /api/v1/admin/config-center/integrations/:id`
4. 建议操作顺序：
   - 先把基础模型提供商配置为可用（`llm.any`）。
   - 再配置企业检索（`kb_search`）。
   - 最后配置行动接口（`notify_send`、`task_create`）。
5. `llm.any` 说明：
   - `llm.any` 是“至少有一个可用 LLM 集成”的逻辑条件，不是额外模型。
   - 例如已配置 `llm.openai` 并校验通过，即可满足 `llm.any`。
   - 如果你已有多个 LLM，可任选其一保持可用状态。

## 11. 工具配置面板 + 状态中心（新版）

1. 入口：
   - 左侧 `配置中心`（仅管理员）。
   - 页面内部有 `总览 / 系统工具 / 外部连接 / 状态中心 / API格式 / 帮助` 六个子面板。
2. 总览（给外行先看）：
   - 展示“已配置连接数 / 待配置项 / 系统配置数 / 外部 API 数 / OAuth 数”。
   - 提供推荐顺序：先配置外部连接必填项，再检查连通性，最后回状态中心看是否清零。
   - 列出“当前配置一览”（每项显示：分类、状态、是否已配置、缺失字段）。
   - 支持一键导出“能力矩阵”到剪贴板（`Markdown` / `CSV`）。
3. 系统工具：
   - 查看每个工具的状态、缺失依赖、最近检查信息。
   - 可直接启用/禁用工具。
4. 外部连接（重点）：
   - 自动按三类分组：
     - `系统配置`：平台内部运行配置
     - `外部 API`：API 地址、API Key、Token 类型
     - `OAuth`：Client ID / Client Secret / Refresh Token 类型
   - 查看每个集成的必填字段缺失情况。
   - 每个字段会显示：配置项说明、通常获取方式、示例格式。
   - 点击 `Configure` 写入密钥（后台加密保存，不回显明文）。
   - 点击 `Check` 触发健康检查（60 秒内重复请求走缓存）。
5. 状态中心：
   - 顶部展示 `OK / WARN / ERROR`。
   - 中部展示“已配置连接数 / OAuth 数 / 外部 API 数”。
   - 下方同时展示“异常与阻塞项” + “当前配置清单”。
6. API格式：
   - 面板内提供常用接口与 JSON 示例，便于对接或排障。
7. 帮助：
   - 展示外行可读的配置说明（先后顺序、字段用途、获取方式、示例）。
8. 旧版清理（本次）：
   - 客户端已不再回退到旧版 `admin/config-center/*` 数据。
   - 配置中心统一以新版接口为准，避免旧数据污染状态。
9. 后端接口（新版）：
   - `GET /api/v1/admin/tools`
   - `GET /api/v1/admin/tools/:id`
   - `POST /api/v1/admin/tools/:id/toggle`
   - `GET /api/v1/admin/integrations`
   - `GET /api/v1/admin/integrations/:id`
   - `POST /api/v1/admin/integrations/:id/secret`
   - `POST /api/v1/admin/integrations/:id/check`
   - `GET /api/v1/admin/status/summary`
10. 常用 API JSON 格式：
   - 保存密钥：
```json
{
  "secret_key_name": "OPENAI_API_KEY",
  "secret_value": "sk-xxxx",
  "display_name": "OpenAI",
  "is_enabled": true
}
```
   - 健康检查返回：
```json
{
  "code": 1,
  "msg": "checked",
  "data": {
    "integration_id": "llm.openai",
    "status": "OK",
    "last_error_code": "",
    "last_error_message": ""
  }
}
```
11. 环境变量：
   - `MASTER_KEY`：密钥加密主密钥（必须配置，建议 32 字节随机值或其 base64）。
   - `AIOC_TOOLS_MANIFEST_FILE`：可选，自定义 tools manifest 路径。

## 11.1 OpenClaw 已注册能力边界（按当前 manifest）

1. 系统内部核心能力（不依赖外部 API）：
   - `openclaw.fs`：文件与产物存储
   - `openclaw.runtime`：运行时编排与执行
2. 系统内部能力（依赖本机组件）：
   - `openclaw.ui.browser`：浏览器自动化（依赖 `playwright` 可执行环境）
3. 新增已注册的系统类能力（不依赖外部 API）：
   - `openclaw.template.apply`：模板渲染
   - `openclaw.output.validate`：输出校验
   - `openclaw.policy.check`：策略检查
   - `openclaw.schedule.create`：调度创建
   - `openclaw.trigger.watch`：触发监听
   - `openclaw.review.request`：人工审批请求
   - `openclaw.execution.pause`：执行暂停/恢复
   - `openclaw.audit.log`：审计记录
   - `openclaw.quota.check`：配额与成本检查
   - `openclaw.secret.resolve`：运行时密钥解析
4. 外部依赖能力（需要外部连接）：
   - `openclaw.web_fetch`（依赖 `search.brave`）
   - `aioc.artifact_render`（依赖 `llm.openai`）
   - `aioc.task.create`（依赖 `task.api`）
   - `ocr_extract`（依赖 `ocr.api`）
   - `asr_transcribe`（依赖 `asr.api`）
   - `tts_synthesize`（依赖 `tts.api`）
5. 结论（能力边界）：
   - OpenClaw 从执行层看可操作系统，但在产品层由“能力注册 + 依赖校验”强约束。
   - 真正可执行能力边界 = 已注册工具集合 ∩ 当前状态为 `OK` 的工具。
   - 注意：已注册不等于已完成执行接入；需结合具体 tool handler/engine 实现判断是否“可真正执行”。
6. 系统内部工具状态异常处理：
   - `MISSING_BINARIES`：安装缺失本机依赖（例如 `playwright`）。
   - `DISABLED`：在配置中心“系统工具”页重新启用。
   - `ERROR`：查看 `last_error_code / last_error_message`，按错误码处理。
   - `MISSING_INTEGRATIONS`：不属于纯内部问题，需补齐外部连接后重检。

## 11.2 Skills 标准文档与外行落地路径

1. 标准文档入口：
   - `docs/SKILL_PRODUCT_STANDARD.md`
   - `docs/OPENCLAW_TOOLING_MANIFEST_GUIDE.md`
2. 你需要先确认两件事：
   - 该 skill 用到的能力是否在 manifest 已注册。
   - 对应外部连接是否已配置并健康检查 `OK`。
3. 外行可按这个顺序执行：
   - 第一步：在 `配置中心 -> 总览` 看“错误/阻塞项”是否清零。
   - 第二步：在 `系统工具` 看所需能力是否 `enabled + OK`。
   - 第三步：在 `外部连接` 补齐必填字段并执行 `Check`。
   - 第四步：回 `状态中心` 确认无 `p0` 阻塞，再发布/执行 skill。
4. 当前能力规模（与面板一致）：
   - 已注册系统+外部能力共 `19` 项。
   - 外部连接配置项共 `6` 项（`llm.openai/search.brave/task.api/ocr.api/asr.api/tts.api`）。

## 12. 图片识别/语音能力（当前阶段）

1. 当前状态：
   - 已接入配置中心可管理能力：OCR（图片转文字）、ASR（语音转文字）、TTS（文字转语音）。
   - 已支持在配置中心中查看状态、录入密钥、执行健康检查。
2. 对应集成项：
   - `ocr.api`（必填：`OCR_API_BASE_URL`、`OCR_API_TOKEN`）
   - `asr.api`（必填：`ASR_API_BASE_URL`、`ASR_API_TOKEN`）
   - `tts.api`（必填：`TTS_API_BASE_URL`、`TTS_API_TOKEN`）
3. 对应工具项：
   - `aioc.ocr.extract`
   - `aioc.asr.transcribe`
   - `aioc.tts.synthesize`
4. 当前可执行能力：
   - `ocr_extract`：图片转文字
   - `asr_transcribe`：语音转文字
   - `tts_synthesize`：文字转语音
5. 运行依赖：
   - OCR/ASR/TTS 所需凭据可通过配置中心写入（加密存储），系统会在任务执行时按租户注入到执行链路。
   - 同时仍兼容引擎进程环境变量作为兜底。
   - 若 provider 未配置，工具会返回明确错误提示，不会静默伪造结果。

## 12.1 OCR/TTS 实际接口配置示例（你当前这套）

1. 适用接口：
   - TTS：`GET http://43.140.221.227:8000/tts?text=...`
   - OCR：`POST http://43.140.221.227:8000/ocr`（`multipart/form-data`，字段 `file`）
2. 配置中心填写（`集成`页）：
   - `ocr.api`
     - `OCR_API_BASE_URL = http://43.140.221.227:8000`
     - `OCR_API_TOKEN` 可留空
   - `tts.api`
     - `TTS_API_BASE_URL = http://43.140.221.227:8000`
     - `TTS_API_TOKEN` 可留空
3. 系统兼容策略（已接入）：
   - `ocr_extract`：
     - 有本地 `image_path` 时，优先按 `multipart/form-data(file=...)` 上传到 `/ocr`
     - 有 `image_url` 时，走 JSON 请求作为回退
   - `tts_synthesize`：
     - 优先尝试 `GET /tts?text=...`
     - 若不兼容，再回退 `POST /tts/synthesize`
4. 你的原始联调用法（留档）：

```bash
# OCR
curl -X 'POST' \
  'http://43.140.221.227:8000/ocr' \
  -H 'accept: application/json' \
  -H 'Content-Type: multipart/form-data' \
  -F 'file=@Screenshot_20260218232610.png;type=image/png'

# TTS
curl 'http://43.140.221.227:8000/tts?text=你好，这是TTS测试'
```

5. 建议测试路径：
   - 先在配置中心保存 `ocr.api`、`tts.api`
   - 在聊天中触发 `ocr_extract` 与 `tts_synthesize`
   - 观察是否返回 OCR 文本和可下载的音频产物

## 13. 配置中心“真实生效”说明

1. 配置中心分两层：
   - 控制面（Control Plane）：配置、密钥、健康检查、依赖状态。
   - 执行面（Execution Plane）：聊天任务里真正调用工具并产出结果。
2. 当前已真实生效的部分：
   - 工具/集成状态计算
   - 凭据配置状态更新（加密存储）
   - 健康检查结果与阻断项显示
   - 任务执行时按租户注入运行时凭据（OCR/ASR/TTS）
3. 仍在完善中的部分：
   - 更广泛工具（如 web_search/browser/artifact_render）的统一凭据注入与执行链路校验
4. 系统提示策略：
   - 配置中心顶部会显示“控制面不等于执行面”的提示。
   - 若某能力仅完成配置接入，状态中心会提示“未接入执行”风险。

## 14. v1 大众版能力边界

1. 当前版本定位大众用户，`channel` 类消息分发配置已从配置中心隐藏。
2. 企业级消息/通知通道将在后续版本按版本策略开放。
