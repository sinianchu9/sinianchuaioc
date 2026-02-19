# Config Center UI Field Mapping

Last updated: 2026-02-19

## Purpose

Map `config_center_status_panel.template.json` fields to front-end panel cards, labels, and status colors.

## Status Color Mapping

- `ok`: green
- `warn`: amber
- `blocked`: red
- `unknown`: gray

## Card Mapping

### 1. Overall Health Card

- Data path: `summary.overall_status`
- Data path: `summary.status_reason`
- Data path: `summary.counts.tools_total`
- Data path: `summary.counts.tools_ready`
- Data path: `summary.counts.tools_blocked`
- Data path: `summary.counts.integrations_total`
- Data path: `summary.counts.integrations_ready`
- Data path: `summary.counts.integrations_missing`
- Data path: `summary.counts.mandatory_missing`

### 2. Bootstrap Checks Card

- Data path: `bootstrap_check_result.executed`
- Data path: `bootstrap_check_result.pass`
- List path: `bootstrap_check_result.rules[]`
- Row fields:
  - `rule_name`
  - `status`
  - `message`
  - `blocking`

### 3. Tools Readiness Table

- List path: `tool_status[]`
- Columns:
  - `tool_id`
  - `category`
  - `status`
  - `enabled`
  - `install_via`
  - `missing_dependencies`
  - `missing_integrations`
  - `notes`

### 4. Integrations Readiness Table

- List path: `integration_status[]`
- Columns:
  - `integration_id`
  - `category`
  - `mandatory`
  - `status`
  - `configured`
  - `last_validated_at`
  - `required_fields`
  - `missing_fields`
  - `notes`

### 5. Workflow Readiness Card

- List path: `workflow_readiness[]`
- Row fields:
  - `workflow_type`
  - `status`
  - `blocking_items`
  - `message`

### 6. Profession Readiness Card

- List path: `profession_readiness[]`
- Row fields:
  - `role_id`
  - `status`
  - `blocking_integrations`
  - `blocking_tools`

### 7. Action Queue Card

- List path: `actions[]`
- Row fields:
  - `action_id`
  - `priority`
  - `type`
  - `target`
  - `message`

## Interaction Rules

- Clicking a blocked integration opens integration setup form prefilled by `required_fields`.
- Clicking a blocked tool shows missing dependency checklist from `missing_dependencies`.
- Clicking a workflow row filters blockers to related integrations and tools.
- Clicking a profession row filters blockers to role-specific missing items.

## Display Priority

- P0: `summary.overall_status`, `mandatory_missing`, `bootstrap_check_result.rules` with `blocking=true`
- P1: `workflow_readiness`, `profession_readiness`
- P2: full tool/integration tables and action queue

