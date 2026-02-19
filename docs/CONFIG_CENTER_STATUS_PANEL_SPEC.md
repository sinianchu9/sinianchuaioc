# Config Center Status Panel Spec

Last updated: 2026-02-19

## Goal

Provide a single status panel that answers:
1. What tools are installed and ready.
2. What admin integrations are configured or missing.
3. Which workflow types are blocked.
4. Which profession skill packs can be released.

## Data Source

1. Static policy source:
- `server/gateway-go/config/openclaw_tooling_manifest.json`

2. Runtime status source:
- `server/gateway-go/config/config_center_status_panel.template.json`
- In production this should be generated at runtime from health checks and integration validation.

## Panel Sections

1. Overall summary
- `overall_status`: `ok | warn | blocked | unknown`
- counts for tools and integrations
- top reason

2. Bootstrap checks
- rule-by-rule pass/fail state
- blocking flag per rule

3. Tool readiness
- one row per tool
- status, install mode, missing dependencies, missing integrations

4. Integration readiness
- one row per integration
- mandatory flag, configured flag, missing required fields

5. Workflow readiness
- readiness for `query`, `generate`, `action`
- each item must list explicit blockers

6. Profession readiness
- readiness for each profession role pack
- blocker lists from dependency and integration gaps

7. Action queue
- prioritized next actions (`p0`, `p1`, `p2`)
- direct linkage to missing item ids

## Status Calculation Rules

1. Tool status
- `blocked`: missing required dependency or required integration
- `warn`: optional dependency missing or degraded mode
- `ok`: all required conditions met
- `unknown`: not checked yet

2. Integration status
- `blocked`: mandatory integration missing or failed validation
- `warn`: optional integration missing
- `ok`: required fields exist and validation passed
- `unknown`: never validated

3. Workflow status
- `blocked`: any mandatory requirement in `workflow_enforcement_rules` cannot be satisfied
- `warn`: base path available but degraded due to optional integrations
- `ok`: all mandatory requirements satisfied

4. Profession status
- `blocked`: missing mandatory integrations for that role
- `warn`: optional capabilities missing
- `ok`: all role requirements satisfied

## Minimum Backend Endpoints (Next)

1. `GET /api/v1/admin/config-center/status`
- returns panel JSON payload

2. `POST /api/v1/admin/config-center/validate`
- triggers bootstrap checks and integration validation

3. `GET /api/v1/admin/config-center/actions`
- returns prioritized action queue

## Release Gate

A profession workflow can be marked release-ready only when:
- workflow status is `ok`, and
- profession status is `ok`, and
- no `p0` action remains unresolved.

