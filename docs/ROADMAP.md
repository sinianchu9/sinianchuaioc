# AIOC Roadmap (Skills over Models)

Last updated: 2026-02-18

## Delivered

### Foundation

- Multi-user auth, sessioning, billing, audit baseline.
- Gateway/Core/Engine layered architecture.
- Chat SSE pipeline and mode routing.

### Skills over Models

- Skills catalog endpoint and client skill picker.
- Skill-driven tool permissions by plan.
- Engine-side allowed-tools enforcement and tool timeline events.
- Initial skill catalog seeded (including baseline skills inspired by `skills.sh`).

### Hardening (P0 done)

- Session update isolation by user.
- Billing idempotency (`request_id` uniqueness + transactional commit).
- JWT token type enforcement in refresh flow.
- Semver-based client version policy.
- Cost limiter connected to actual request cost.
- Tool execution safety tightened.

### Adaptive Workspace (Phase 2.2)

- Master-Detail project navigation flow.
- Strict session isolation and history visibility for draft chat.
- Cascade project deletion API and UI.

### Automations (MVP)

- Automation CRUD.
- Run-now execution and run history tracking.
- Client automation management UI.

## In Progress

- 加速高频职业技能向严格 Workflow Contracts 转化 (产品价值升级)。
- 增加资料库到项目的“一键创建”引导 UX，降低用户认知负担 (UX优化)。
- Timed automation scheduler worker (server-side recurring trigger)。
- Extended negative tests for isolation and replay conditions。
- Connector bridge (user-managed API keys) with encrypted storage。

## Next Milestones

### M1: Production Readiness Gate

- Scheduler + retry strategy + dead-letter handling，完成自动化闭环 (PM要求)。
- 控制面与执行面一致性保障，增加外部 API 调用的限流兜底/熔断机制 (PM要求)。
- `CommitUsage` 热点并发性能优化，探索基于消息队列的异步最终一致性 (Code要求)。
- Metrics/alerts baseline (latency, error rate, billing drift, tool failure).
- End-to-end migration verification on upgrade paths.
- Security review pass for command/tool policy and secret management.

### M2: Monetization and Growth

- Live IAP verification.
- Tiered feature controls refinement by plan.
- Usage and cost transparency dashboards.

### M3: Enterprise Track

- SSO/SAML/LDAP.
- policy/audit export.
- private deployment playbooks (including k8s/helm).
