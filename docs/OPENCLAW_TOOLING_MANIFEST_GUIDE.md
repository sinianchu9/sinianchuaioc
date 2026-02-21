# OpenClaw 能力清单与依赖指南

Last updated: 2026-02-21

## 1. 目的

本指南说明 AIOC 如何基于 manifest 管理“能力注册、依赖校验、配置就绪度、发布门禁”。

当前权威来源：
- `server/gateway-go/config/tools.manifest.yaml`

关联文档：
- `docs/SKILL_PRODUCT_STANDARD.md`
- `docs/CONFIG_CENTER_STATUS_PANEL_SPEC.md`
- `docs/CONFIG_CENTER_UI_FIELD_MAPPING.md`

## 2. manifest 结构

`tools.manifest.yaml` 包含两大部分。

1. `tools`
- 定义能力（工具）注册项
- 关键字段：
  - `id`
  - `category`
  - `default_enabled`
  - `risk_level`
  - `dependencies.binaries`
  - `dependencies.all_of_integrations`
  - `dependencies.any_of_integrations`

2. `integrations`
- 定义外部连接配置项
- 关键字段：
  - `id`
  - `type`
  - `required_fields`
  - `field_specs`
  - `check_type`
  - `mandatory`

## 3. 状态计算核心规则

1. 能力状态（tool）
- `OK`：依赖满足且能力启用
- `ERROR`：缺依赖/运行异常
- `DISABLED`：管理员关闭

2. 连接状态（integration）
- `configured=true` 仅表示字段已填写
- `status=OK` 才表示检查通过、可用于执行

3. 可执行边界
- 真正可执行能力 = 已注册能力 ∩ `enabled=true` ∩ `status=OK`

## 4. Skills 发布门禁

一个 skill 可以发布前，必须满足：
- skill 声明的 `required_tools` 都存在于 manifest
- 所依赖 integration 已配置并检查通过
- 配置中心无未处理 `p0` 阻塞项
- 运行时质量门禁（产物/动作/审计）可通过

若不满足，应该阻止发布并给出明确错误项（缺能力、缺连接、连接失败、策略不通过）。

## 5. 配置中心如何使用这份 manifest

1. 总览
- 统计系统工具、外部连接、阻塞项
- 显示能力边界与当前可执行范围

2. 系统工具
- 按 `tools` 展示每个能力状态
- 发现 `MISSING_BINARIES` 时提示本机依赖安装

3. 外部连接
- 按 `integrations` 渲染字段表单
- 使用 `field_specs` 给外行展示“用途/获取方式/示例”

4. 状态中心
- 汇总 `ERROR/WARN/OK`
- 给出按优先级排序的修复动作

## 6. 运维排查建议

1. 能力已注册但面板看不到
- 检查服务是否重启并重新加载 manifest
- 检查是否设置了 `AIOC_TOOLS_MANIFEST_FILE` 指向旧文件

2. 面板显示“已配置”但执行失败
- 优先看 integration `status` 是否为 `OK`
- 再看工具执行链路是否已接入（仅注册不等于可执行）

3. 系统类能力异常
- `MISSING_BINARIES`：安装缺失组件
- `DISABLED`：在配置中心重新启用
- `ERROR`：查看 `last_error_code/last_error_message` 逐项修复

## 7. 与 skills 标准的关系

- manifest 负责“能力边界和依赖事实”
- skill 合同负责“业务流程和证据要求”
- 两者组合，才构成可上线的生产级 skill
