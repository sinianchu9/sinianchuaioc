package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
)

type ConfigCenterHandler struct {
	manifestPath string
	statusPath   string
	mu           sync.Mutex
}

func NewConfigCenterHandler() *ConfigCenterHandler {
	return &ConfigCenterHandler{
		manifestPath: resolveFirstExistingPath(
			os.Getenv("AIOC_TOOLING_MANIFEST_FILE"),
			"server/gateway-go/config/openclaw_tooling_manifest.json",
			"config/openclaw_tooling_manifest.json",
			"/app/config/openclaw_tooling_manifest.json",
		),
		statusPath: resolveFirstExistingPath(
			os.Getenv("AIOC_CONFIG_CENTER_STATUS_FILE"),
			"server/gateway-go/config/config_center_status_panel.template.json",
			"config/config_center_status_panel.template.json",
			"/app/config/config_center_status_panel.template.json",
		),
	}
}

func resolveFirstExistingPath(candidates ...string) string {
	for _, p := range candidates {
		if strings.TrimSpace(p) == "" {
			continue
		}
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	for _, p := range candidates {
		if strings.TrimSpace(p) != "" {
			return p
		}
	}
	return ""
}

func hasAdminRole(c *gin.Context) bool {
	rolesRaw, ok := c.Get("roles")
	if !ok {
		return false
	}
	roles, ok := rolesRaw.([]string)
	if !ok {
		return false
	}
	for _, r := range roles {
		if strings.EqualFold(r, "admin") {
			return true
		}
	}
	return false
}

func denyIfNotAdmin(c *gin.Context) bool {
	if hasAdminRole(c) {
		return false
	}
	c.JSON(http.StatusForbidden, models.APIResponse{
		Code:    0,
		Msg:     "admin role required",
		TraceID: c.GetString("trace_id"),
	})
	return true
}

func readJSONFile(path string) (map[string]any, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	b = bytesTrimBOM(b)
	var out map[string]any
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func bytesTrimBOM(b []byte) []byte {
	if len(b) >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF {
		return b[3:]
	}
	return b
}

func writeJSONFile(path string, data map[string]any) error {
	if path == "" {
		return errors.New("empty file path")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	return os.WriteFile(path, b, 0o644)
}

func (h *ConfigCenterHandler) getManifest() (map[string]any, error) {
	return readJSONFile(h.manifestPath)
}

func (h *ConfigCenterHandler) getStatus() (map[string]any, error) {
	return readJSONFile(h.statusPath)
}

func (h *ConfigCenterHandler) saveStatus(status map[string]any) error {
	return writeJSONFile(h.statusPath, status)
}

func mapSlice(v any) []map[string]any {
	raw, ok := v.([]any)
	if !ok {
		return []map[string]any{}
	}
	out := make([]map[string]any, 0, len(raw))
	for _, item := range raw {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		out = append(out, m)
	}
	return out
}

func findIntegration(integrations []map[string]any, id string) map[string]any {
	for _, it := range integrations {
		if s, _ := it["integration_id"].(string); s == id {
			return it
		}
	}
	return nil
}

func containsString(list []string, target string) bool {
	for _, v := range list {
		if v == target {
			return true
		}
	}
	return false
}

func toStringSlice(v any) []string {
	raw, ok := v.([]any)
	if !ok {
		return []string{}
	}
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		s, ok := item.(string)
		if ok && s != "" {
			out = append(out, s)
		}
	}
	return out
}

func setMapSlice(m map[string]any, key string, v []map[string]any) {
	out := make([]any, 0, len(v))
	for _, it := range v {
		out = append(out, it)
	}
	m[key] = out
}

func (h *ConfigCenterHandler) recompute(manifest, status map[string]any) {
	now := time.Now().UTC().Format(time.RFC3339)
	status["last_refresh_at"] = now

	manifestIntegrations := mapSlice(manifest["admin_provided_api_integrations"])
	statusIntegrationsRaw := mapSlice(status["integration_status"])
	manifestIntegrationIDs := map[string]bool{}
	for _, mi := range manifestIntegrations {
		if id, _ := mi["integration_id"].(string); id != "" {
			manifestIntegrationIDs[id] = true
		}
	}
	statusIntegrations := make([]map[string]any, 0, len(statusIntegrationsRaw))
	for _, si := range statusIntegrationsRaw {
		id, _ := si["integration_id"].(string)
		if id != "" && manifestIntegrationIDs[id] {
			statusIntegrations = append(statusIntegrations, si)
		}
	}

	// Ensure every manifest integration has status row.
	for _, mi := range manifestIntegrations {
		id, _ := mi["integration_id"].(string)
		if id == "" {
			continue
		}
		if findIntegration(statusIntegrations, id) != nil {
			continue
		}
		required := toStringSlice(mi["required_fields"])
		row := map[string]any{
			"integration_id":    id,
			"category":          mi["category"],
			"mandatory":         mi["mandatory"],
			"status":            "unknown",
			"configured":        false,
			"last_validated_at": "",
			"required_fields":   required,
			"missing_fields":    required,
			"notes":             "",
		}
		statusIntegrations = append(statusIntegrations, row)
	}

	// Pass 1: evaluate direct integrations.
	configuredIntegrationIDs := map[string]bool{}
	mandatoryMissing := 0
	for _, si := range statusIntegrations {
		id, _ := si["integration_id"].(string)
		mi := findIntegration(manifestIntegrations, id)
		if mi == nil {
			continue
		}
		mandatory, _ := mi["mandatory"].(bool)
		required := toStringSlice(mi["required_fields"])
		configured, _ := si["configured"].(bool)
		missing := toStringSlice(si["missing_fields"])

		if configured && len(missing) == 0 {
			si["status"] = "ok"
			configuredIntegrationIDs[id] = true
		} else if mandatory {
			si["status"] = "blocked"
			mandatoryMissing++
		} else if configured {
			si["status"] = "warn"
		} else {
			si["status"] = "warn"
		}
		if len(required) > 0 && missing == nil {
			si["missing_fields"] = required
		}
		if _, ok := si["last_validated_at"]; !ok {
			si["last_validated_at"] = now
		}
	}

	// Pass 2: evaluate constraint integrations like llm.any
	for _, si := range statusIntegrations {
		id, _ := si["integration_id"].(string)
		mi := findIntegration(manifestIntegrations, id)
		if mi == nil {
			continue
		}
		constraint, _ := mi["constraint"].(map[string]any)
		if constraint == nil {
			continue
		}
		anyOf := toStringSlice(constraint["any_of"])
		anyConfigured := false
		for _, dep := range anyOf {
			if configuredIntegrationIDs[dep] {
				anyConfigured = true
				break
			}
		}
		si["configured"] = anyConfigured
		if anyConfigured {
			si["status"] = "ok"
			configuredIntegrationIDs[id] = true
		} else {
			si["status"] = "blocked"
			mandatory, _ := mi["mandatory"].(bool)
			if mandatory {
				mandatoryMissing++
			}
		}
		si["last_validated_at"] = now
	}
	setMapSlice(status, "integration_status", statusIntegrations)

	manifestTools := mapSlice(manifest["system_init_install_tools"])
	statusToolsRaw := mapSlice(status["tool_status"])
	manifestToolIDs := map[string]bool{}
	for _, mt := range manifestTools {
		if id, _ := mt["tool_id"].(string); id != "" {
			manifestToolIDs[id] = true
		}
	}
	statusTools := make([]map[string]any, 0, len(statusToolsRaw))
	for _, st := range statusToolsRaw {
		id, _ := st["tool_id"].(string)
		if id != "" && manifestToolIDs[id] {
			statusTools = append(statusTools, st)
		}
	}
	toolByID := map[string]map[string]any{}
	for _, mt := range manifestTools {
		if id, _ := mt["tool_id"].(string); id != "" {
			toolByID[id] = mt
		}
	}
	// ensure every tool has status row
	for id, mt := range toolByID {
		found := false
		for _, st := range statusTools {
			if sid, _ := st["tool_id"].(string); sid == id {
				found = true
				break
			}
		}
		if found {
			continue
		}
		install := map[string]any{}
		if v, ok := mt["install"].(map[string]any); ok {
			install = v
		}
		statusTools = append(statusTools, map[string]any{
			"tool_id":              id,
			"category":             mt["category"],
			"status":               "unknown",
			"enabled":              true,
			"install_via":          install["via"],
			"missing_dependencies": []any{},
			"missing_integrations": []any{},
			"notes":                "",
		})
	}

	depMap, _ := manifest["dependency_map"].(map[string]any)
	toolBlocked := 0
	toolReady := 0
	for _, st := range statusTools {
		id, _ := st["tool_id"].(string)
		mt := toolByID[id]
		if mt == nil {
			continue
		}
		statusVal, _ := st["status"].(string)
		missingDeps := toStringSlice(st["missing_dependencies"])
		missingInts := []string{}

		// dependency map check
		if depMap != nil {
			if dep, ok := depMap[id].(map[string]any); ok {
				if anyOf := toStringSlice(dep["any_of_integrations"]); len(anyOf) > 0 {
					anyConfigured := false
					for _, item := range anyOf {
						if configuredIntegrationIDs[item] {
							anyConfigured = true
							break
						}
					}
					if !anyConfigured {
						missingInts = append(missingInts, anyOf...)
					}
				}
				if allOf := toStringSlice(dep["all_of_integrations"]); len(allOf) > 0 {
					for _, item := range allOf {
						if !configuredIntegrationIDs[item] {
							missingInts = append(missingInts, item)
						}
					}
				}
			}
		}
		uniqMissingInts := make([]string, 0, len(missingInts))
		for _, s := range missingInts {
			if !containsString(uniqMissingInts, s) {
				uniqMissingInts = append(uniqMissingInts, s)
			}
		}
		st["missing_integrations"] = uniqMissingInts

		if len(missingDeps) > 0 {
			statusVal = "blocked"
		} else if len(uniqMissingInts) > 0 {
			adm, _ := mt["admin_provided"].(bool)
			if adm {
				statusVal = "blocked"
			} else {
				statusVal = "warn"
			}
		} else if statusVal == "" || statusVal == "unknown" {
			statusVal = "ok"
		}
		st["status"] = statusVal
		if statusVal == "blocked" {
			toolBlocked++
		}
		if statusVal == "ok" {
			toolReady++
		}
	}
	setMapSlice(status, "tool_status", statusTools)

	workflowReadiness := mapSlice(status["workflow_readiness"])
	if len(workflowReadiness) == 0 {
		workflowReadiness = []map[string]any{
			{"workflow_type": "query"},
			{"workflow_type": "generate"},
			{"workflow_type": "action"},
		}
	}
	for _, wr := range workflowReadiness {
		wf, _ := wr["workflow_type"].(string)
		blockers := []string{}
		switch wf {
		case "query":
			if !configuredIntegrationIDs["kb_search"] {
				blockers = append(blockers, "kb_search")
			}
		case "generate":
			for _, st := range statusTools {
				if sid, _ := st["tool_id"].(string); sid == "artifact_render" {
					if sv, _ := st["status"].(string); sv == "blocked" {
						blockers = append(blockers, "artifact_render")
					}
				}
			}
		case "action":
			if !configuredIntegrationIDs["notify_send"] {
				blockers = append(blockers, "notify_send")
			}
			if !configuredIntegrationIDs["task_create"] {
				blockers = append(blockers, "task_create")
			}
		}
		if len(blockers) > 0 {
			wr["status"] = "blocked"
			wr["blocking_items"] = blockers
			wr["message"] = "missing mandatory dependencies"
		} else {
			wr["status"] = "ok"
			wr["blocking_items"] = []any{}
			wr["message"] = "ready"
		}
	}
	setMapSlice(status, "workflow_readiness", workflowReadiness)

	// profession readiness based on required_for_professions in manifest integrations.
	roleSet := []string{"student", "teacher", "doctor", "lawyer", "accountant", "support", "ecommerce"}
	professionReadiness := make([]map[string]any, 0, len(roleSet))
	for _, role := range roleSet {
		blockingInts := []string{}
		for _, mi := range manifestIntegrations {
			reqRoles := toStringSlice(mi["required_for_professions"])
			mandatory, _ := mi["mandatory"].(bool)
			if !mandatory || len(reqRoles) == 0 || !containsString(reqRoles, role) {
				continue
			}
			id, _ := mi["integration_id"].(string)
			if !configuredIntegrationIDs[id] {
				blockingInts = append(blockingInts, id)
			}
		}
		row := map[string]any{
			"role_id":               role,
			"blocking_integrations": blockingInts,
			"blocking_tools":        []any{},
		}
		if len(blockingInts) > 0 {
			row["status"] = "blocked"
		} else {
			row["status"] = "ok"
		}
		professionReadiness = append(professionReadiness, row)
	}
	setMapSlice(status, "profession_readiness", professionReadiness)

	// Bootstrap checks.
	bootstrap, _ := status["bootstrap_check_result"].(map[string]any)
	if bootstrap == nil {
		bootstrap = map[string]any{}
	}
	rules := mapSlice(bootstrap["rules"])
	bootstrapPass := true
	for _, r := range rules {
		name, _ := r["rule_name"].(string)
		switch {
		case strings.Contains(name, "llm provider"):
			if configuredIntegrationIDs["llm.any"] {
				r["status"] = "ok"
				r["message"] = "constraint satisfied"
			} else {
				r["status"] = "blocked"
				r["message"] = "no LLM provider configured"
				bootstrapPass = false
			}
		case strings.Contains(name, "browser enabled"):
			browserBlocked := false
			for _, st := range statusTools {
				if sid, _ := st["tool_id"].(string); sid == "browser" {
					if sv, _ := st["status"].(string); sv == "blocked" {
						browserBlocked = true
					}
				}
			}
			if browserBlocked {
				r["status"] = "blocked"
				r["message"] = "browser dependencies missing"
				bootstrapPass = false
			} else {
				r["status"] = "ok"
				r["message"] = "browser dependencies ready"
			}
		case strings.Contains(name, "enterprise query"):
			if configuredIntegrationIDs["kb_search"] {
				r["status"] = "ok"
				r["message"] = "kb_search configured"
			} else {
				r["status"] = "blocked"
				r["message"] = "kb_search missing"
				bootstrapPass = false
			}
		case strings.Contains(name, "enterprise action"):
			if configuredIntegrationIDs["notify_send"] && configuredIntegrationIDs["task_create"] {
				r["status"] = "ok"
				r["message"] = "notify_send and task_create configured"
			} else {
				r["status"] = "blocked"
				r["message"] = "notify_send or task_create missing"
				bootstrapPass = false
			}
		default:
			if s, _ := r["status"].(string); s == "" {
				r["status"] = "unknown"
			}
		}
	}
	setMapSlice(bootstrap, "rules", rules)
	bootstrap["executed"] = true
	bootstrap["pass"] = bootstrapPass
	status["bootstrap_check_result"] = bootstrap

	// Summary and action queue.
	integrationTotal := len(statusIntegrations)
	integrationReady := 0
	integrationMissing := 0
	for _, si := range statusIntegrations {
		s, _ := si["status"].(string)
		if s == "ok" {
			integrationReady++
		}
		if s == "blocked" || s == "warn" {
			integrationMissing++
		}
	}
	summary := map[string]any{
		"counts": map[string]any{
			"tools_total":          len(statusTools),
			"tools_ready":          toolReady,
			"tools_blocked":        toolBlocked,
			"integrations_total":   integrationTotal,
			"integrations_ready":   integrationReady,
			"integrations_missing": integrationMissing,
			"mandatory_missing":    mandatoryMissing,
		},
	}
	if !bootstrapPass || mandatoryMissing > 0 {
		summary["overall_status"] = "blocked"
		summary["status_reason"] = "missing mandatory integrations"
	} else if toolBlocked > 0 {
		summary["overall_status"] = "warn"
		summary["status_reason"] = "some tools are blocked"
	} else {
		summary["overall_status"] = "ok"
		summary["status_reason"] = "all mandatory checks passed"
	}
	status["summary"] = summary

	actions := make([]any, 0)
	if !configuredIntegrationIDs["llm.any"] {
		actions = append(actions, map[string]any{
			"action_id": "configure_llm_provider",
			"priority":  "p0",
			"type":      "integration_setup",
			"target":    "llm.any",
			"message":   "configure at least one LLM provider",
		})
	}
	if !configuredIntegrationIDs["kb_search"] {
		actions = append(actions, map[string]any{
			"action_id": "configure_enterprise_query",
			"priority":  "p0",
			"type":      "integration_setup",
			"target":    "kb_search",
			"message":   "configure enterprise retrieval API",
		})
	}
	if !configuredIntegrationIDs["notify_send"] || !configuredIntegrationIDs["task_create"] {
		actions = append(actions, map[string]any{
			"action_id": "configure_enterprise_action",
			"priority":  "p0",
			"type":      "integration_setup",
			"target":    "notify_send+task_create",
			"message":   "configure enterprise action APIs",
		})
	}
	status["actions"] = actions
}

func (h *ConfigCenterHandler) GetManifest(c *gin.Context) {
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	data, err := h.getManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to read tooling manifest", TraceID: traceID})
		return
	}
	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: data, TraceID: traceID})
}

func (h *ConfigCenterHandler) GetStatus(c *gin.Context) {
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	h.mu.Lock()
	defer h.mu.Unlock()
	manifest, err := h.getManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to read tooling manifest", TraceID: traceID})
		return
	}
	status, err := h.getStatus()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to read config center status", TraceID: traceID})
		return
	}
	h.recompute(manifest, status)
	_ = h.saveStatus(status)
	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: status, TraceID: traceID})
}

type updateIntegrationRequest struct {
	Configured    *bool    `json:"configured"`
	MissingFields []string `json:"missing_fields"`
	Notes         string   `json:"notes"`
}

func (h *ConfigCenterHandler) UpdateIntegration(c *gin.Context) {
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	integrationID := c.Param("id")
	if integrationID == "" {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid integration id", TraceID: traceID})
		return
	}

	var req updateIntegrationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid request: " + err.Error(), TraceID: traceID})
		return
	}

	h.mu.Lock()
	defer h.mu.Unlock()
	manifest, err := h.getManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to read tooling manifest", TraceID: traceID})
		return
	}
	status, err := h.getStatus()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to read config center status", TraceID: traceID})
		return
	}

	integrations := mapSlice(status["integration_status"])
	row := findIntegration(integrations, integrationID)
	if row == nil {
		c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "integration not found", TraceID: traceID})
		return
	}
	if req.Configured != nil {
		row["configured"] = *req.Configured
	}
	if req.MissingFields != nil {
		out := make([]any, 0, len(req.MissingFields))
		for _, s := range req.MissingFields {
			if strings.TrimSpace(s) != "" {
				out = append(out, strings.TrimSpace(s))
			}
		}
		row["missing_fields"] = out
	}
	if req.Notes != "" || req.Notes == "" {
		row["notes"] = req.Notes
	}
	row["last_validated_at"] = time.Now().UTC().Format(time.RFC3339)
	setMapSlice(status, "integration_status", integrations)

	h.recompute(manifest, status)
	if err := h.saveStatus(status); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to write config center status", TraceID: traceID})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "integration updated", Data: status, TraceID: traceID})
}

func (h *ConfigCenterHandler) Validate(c *gin.Context) {
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	h.mu.Lock()
	defer h.mu.Unlock()
	manifest, err := h.getManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to read tooling manifest", TraceID: traceID})
		return
	}
	status, err := h.getStatus()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to read config center status", TraceID: traceID})
		return
	}
	h.recompute(manifest, status)
	if err := h.saveStatus(status); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to write config center status", TraceID: traceID})
		return
	}
	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "validation completed", Data: status, TraceID: traceID})
}
