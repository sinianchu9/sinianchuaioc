# OpenClaw Tooling Manifest Guide

Last updated: 2026-02-19

## Purpose

This guide explains how AIOC uses:
- `server/gateway-go/config/openclaw_tooling_manifest.json`

The manifest provides two required outputs:
1. Tools the system can install/enable directly at initialization.
2. API integrations admins must provide before profession skills are executable.

Status panel companion:
- `server/gateway-go/config/config_center_status_panel.template.json`
- `docs/CONFIG_CENTER_STATUS_PANEL_SPEC.md`
- `docs/CONFIG_CENTER_UI_FIELD_MAPPING.md`

## Sections

1. `system_init_install_tools`
- Source of truth for tool bootstrap.
- Used by platform bootstrap checklists and deployment scripts.
- Each item defines:
  - `tool_id`
  - `category`
  - `workflow_types`
  - `runtime_requirements`
  - `required_config_keys`
  - `admin_provided`

2. `admin_provided_api_integrations`
- Source of truth for admin onboarding requirements.
- Used by admin panel/checklists to collect credentials and API endpoints.
- Each item defines:
  - `integration_id`
  - `category`
  - `required_for_professions`
  - `required_fields`
  - `tool_aliases`
  - `mandatory`

3. `workflow_enforcement_rules`
- Policy requirements for workflow-oriented skill execution.
- Defines hard pass/fail criteria for:
  - `query` steps
  - `generate` steps
  - `action` steps

4. `dependency_map`
- Declares dependency relationships between tools and integrations.
- Supports `any_of` and `all_of` style checks.
- Used by bootstrap to disable tools with missing dependencies.

5. `bootstrap_checks`
- Startup validation rules.
- Supports:
  - required sections
  - conditional checks by enabled tool
  - conditional checks by workflow type

6. `skill_binding_policy`
- Rules for skill-to-tool binding.
- Prevents undeclared tools from being referenced by production skills.

## Operating Rule

A profession skill is not considered production-ready unless:
- all required tools in `system_init_install_tools` are available, and
- all mandatory entries in `admin_provided_api_integrations` are configured, and
- run traces satisfy `workflow_enforcement_rules`.

## Next Integration Plan

Phase 1: Bootstrap and visibility
- Parse `openclaw_tooling_manifest.json` at system startup.
- Build a runtime status table:
  - installed tools
  - missing dependencies
  - missing admin integrations
- Expose status for admin UI/checklist.

Phase 2: Admin integration onboarding
- Add admin form generated from `admin_provided_api_integrations`.
- Persist integration readiness state per environment/tenant.
- Run `bootstrap_checks` after save and show blocking errors.

Phase 3: Skill contract gating
- Validate each workflow skill against `skill_binding_policy`.
- Reject publish if required tools are missing in manifest.
- Enforce `workflow_enforcement_rules` at runtime before marking success.

Phase 4: Progressive rollout
- Start with student/teacher top workflows.
- Add doctor/lawyer/accountant/support/ecommerce in batches.
- Track failure codes and missing dependency patterns for each batch.
