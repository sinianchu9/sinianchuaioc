# AIOC 操作手册（职业场景版）

Last updated: 2026-02-19

## 1. 登录与入口
1. 登录后进入系统主界面。
2. 左侧核心入口：`聊天`、`使用场景`、`资料`、`项目`。

## 2. 使用场景（技能执行）
1. 打开 `使用场景`。
2. 选择职业与任务（如学生/老师/律师等）。
3. 选择项目（重要）。
4. 进入 `聊天` 发送任务指令，系统会按 `role + task + project` 执行。

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
3. 打开项目对话。
4. 在 `使用场景` 选技能任务并执行。
5. 下载输出结果（docx/xlsx/pdf/zip 等）。

## 6. 常见问题
1. 添加资料后看不到：
   - 点击 `资料` 页 `刷新`。
   - 检查是否有错误提示条。
2. 项目里不能操作：
   - 先选择一个项目。
   - 确保资料库里有可加入条目。
3. Flutter VM Service 报错（`Invalid WebSocket upgrade request`）：
   - 使用固定端口启动：`flutter run --host-vmservice-port 8181`
   - Web 可加：`flutter run -d chrome --web-port 7357`
4. 创建项目时报 `Invalid JSON response status 404`：
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

## 11. 工具配置面板 + 状态中心（新版）
1. 入口：
   - 左侧 `配置中心`（仅管理员）。
   - 页面内部有 `Tools / Integrations / Status` 三个子面板。
2. Tools：
   - 查看每个工具的状态、缺失依赖、最近检查信息。
   - 可直接启用/禁用工具。
3. Integrations：
   - 查看每个集成的必填字段缺失情况。
   - 点击 `Configure` 写入密钥（后台加密保存，不回显明文）。
   - 点击 `Check` 触发健康检查（60 秒内重复请求走缓存）。
4. Status：
   - 顶部展示 `OK / WARN / ERROR` 卡片。
   - 下方按严重级别展示问题列表。
5. 后端接口（新版）：
   - `GET /api/v1/admin/tools`
   - `GET /api/v1/admin/tools/:id`
   - `POST /api/v1/admin/tools/:id/toggle`
   - `GET /api/v1/admin/integrations`
   - `GET /api/v1/admin/integrations/:id`
   - `POST /api/v1/admin/integrations/:id/secret`
   - `POST /api/v1/admin/integrations/:id/check`
   - `GET /api/v1/admin/status/summary`
6. 环境变量：
   - `MASTER_KEY`：密钥加密主密钥（必须配置，建议 32 字节随机值或其 base64）。
   - `AIOC_TOOLS_MANIFEST_FILE`：可选，自定义 tools manifest 路径。

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
   - 引擎需要可用的 OCR/ASR/TTS provider 配置（当前通过引擎运行环境变量读取）。
   - 若 provider 未配置，工具会返回明确错误提示，不会静默伪造结果。

## 13. 配置中心“真实生效”说明
1. 配置中心分两层：
   - 控制面（Control Plane）：配置、密钥、健康检查、依赖状态。
   - 执行面（Execution Plane）：聊天任务里真正调用工具并产出结果。
2. 当前已真实生效的部分：
   - 工具/集成状态计算
   - 凭据配置状态更新
   - 健康检查结果与阻断项显示
3. 需要额外接入才会真实执行的部分：
   - OCR/ASR/TTS 在任务执行中实际调用（core/engine 工具绑定）
4. 系统提示策略：
   - 配置中心顶部会显示“控制面不等于执行面”的提示。
   - 若某能力仅完成配置接入，状态中心会提示“未接入执行”风险。

## 14. v1 大众版能力边界
1. 当前版本定位大众用户，`channel` 类消息分发配置已从配置中心隐藏。
2. 企业级消息/通知通道将在后续版本按版本策略开放。
