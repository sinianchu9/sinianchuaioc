package handlers

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"gopkg.in/yaml.v3"
)

const (
	statusOK                 = "OK"
	statusWarn               = "WARN"
	statusError              = "ERROR"
	statusDisabled           = "DISABLED"
	statusMissingCredentials = "MISSING_CREDENTIALS"
	statusMisconfigured      = "MISCONFIGURED"
)

type ToolControlCenterHandler struct {
	db           *pgxpool.Pool
	manifestPath string
	checkMu      sync.Mutex
	checkCache   map[string]checkCacheEntry
}

type checkCacheEntry struct {
	Status    string
	ErrorCode string
	ErrorMsg  string
	CheckedAt time.Time
	ExpiresAt time.Time
}

type toolManifest struct {
	Tools         []toolManifestItem            `yaml:"tools"`
	Integrations  []integrationManifestItem     `yaml:"integrations"`
	DependencyMap map[string]toolDependencyRule `yaml:"dependency_map"`
}

type toolManifestItem struct {
	ID             string             `yaml:"id"`
	Name           string             `yaml:"name"`
	Category       string             `yaml:"category"`
	Description    string             `yaml:"description"`
	DefaultEnabled bool               `yaml:"default_enabled"`
	RiskLevel      string             `yaml:"risk_level"`
	Dependencies   toolDependencyRule `yaml:"dependencies"`
}

type toolDependencyRule struct {
	AllOfIntegrations []string `yaml:"all_of_integrations"`
	AnyOfIntegrations []string `yaml:"any_of_integrations"`
	Binaries          []string `yaml:"binaries"`
}

type integrationManifestItem struct {
	ID             string                 `yaml:"id"`
	Type           string                 `yaml:"type"`
	DisplayName    string                 `yaml:"display_name"`
	Category       string                 `yaml:"category"`
	Description    string                 `yaml:"description"`
	RequiredFields []string               `yaml:"required_fields"`
	OptionalFields []string               `yaml:"optional_fields"`
	FieldSpecs     []integrationFieldSpec `yaml:"field_specs"`
	CheckType      string                 `yaml:"check_type"`
	DefaultEnabled bool                   `yaml:"default_enabled"`
	Mandatory      bool                   `yaml:"mandatory"`
}

type integrationFieldSpec struct {
	Name        string `yaml:"name"`
	Label       string `yaml:"label"`
	Description string `yaml:"description"`
	AcquireHint string `yaml:"acquire_hint"`
	Example     string `yaml:"example"`
	Sensitive   bool   `yaml:"sensitive"`
}

type integrationRow struct {
	ID               string
	Type             string
	DisplayName      string
	IsEnabled        bool
	Status           string
	LastCheckAt      *time.Time
	LastErrorCode    string
	LastErrorMessage string
}

type toolRow struct {
	ToolID           string
	IsEnabled        bool
	Status           string
	LastCheckAt      *time.Time
	LastErrorCode    string
	LastErrorMessage string
}

type integrationState struct {
	Manifest         integrationManifestItem
	Row              integrationRow
	MissingFields    []string
	MaskedConfigured bool
}

type toolState struct {
	Manifest            toolManifestItem
	Row                 toolRow
	ResolvedStatus      string
	MissingIntegrations []string
	MissingBinaries     []string
	LastErrorCode       string
	LastErrorMessage    string
	LastCheckAtISO      string
	Enabled             bool
}

type toggleToolRequest struct {
	Enabled bool `json:"enabled"`
}

type updateIntegrationSecretRequest struct {
	SecretKeyName string `json:"secret_key_name" binding:"required,min=2,max=128"`
	SecretValue   string `json:"secret_value" binding:"required,min=1,max=8192"`
	DisplayName   string `json:"display_name"`
	IsEnabled     *bool  `json:"is_enabled"`
}

func NewToolControlCenterHandler(db *pgxpool.Pool) *ToolControlCenterHandler {
	h := &ToolControlCenterHandler{
		db: db,
		manifestPath: resolveFirstExistingPath(
			os.Getenv("AIOC_TOOLS_MANIFEST_FILE"),
			"server/gateway-go/config/tools.manifest.yaml",
			"config/tools.manifest.yaml",
			"/app/config/tools.manifest.yaml",
		),
		checkCache: map[string]checkCacheEntry{},
	}
	h.ensureSchema()
	return h
}

func (h *ToolControlCenterHandler) ensureSchema() {
	_, _ = h.db.Exec(context.Background(), `
CREATE TABLE IF NOT EXISTS integrations (
	id                 VARCHAR(128) NOT NULL,
	tenant_id          UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
	type               VARCHAR(64) NOT NULL,
	display_name       VARCHAR(255) NOT NULL,
	is_enabled         BOOLEAN NOT NULL DEFAULT TRUE,
	status             VARCHAR(32) NOT NULL DEFAULT 'MISSING_CREDENTIALS',
	last_check_at      TIMESTAMPTZ,
	last_error_code    VARCHAR(64) NOT NULL DEFAULT '',
	last_error_message TEXT NOT NULL DEFAULT '',
	created_by         UUID REFERENCES users(user_id),
	updated_by         UUID REFERENCES users(user_id),
	created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	PRIMARY KEY (tenant_id, id)
)`)
	_, _ = h.db.Exec(context.Background(), `
CREATE TABLE IF NOT EXISTS integration_secrets (
	integration_id     VARCHAR(128) NOT NULL,
	tenant_id          UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
	secret_key_name    VARCHAR(128) NOT NULL,
	secret_ciphertext  TEXT NOT NULL,
	secret_last4       VARCHAR(4) NOT NULL DEFAULT '',
	rotated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	rotated_by         UUID REFERENCES users(user_id),
	PRIMARY KEY (tenant_id, integration_id, secret_key_name),
	FOREIGN KEY (tenant_id, integration_id) REFERENCES integrations(tenant_id, id) ON DELETE CASCADE
)`)
	_, _ = h.db.Exec(context.Background(), `
CREATE TABLE IF NOT EXISTS tool_status (
	tool_id             VARCHAR(128) NOT NULL,
	tenant_id           UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
	is_enabled          BOOLEAN NOT NULL DEFAULT TRUE,
	status              VARCHAR(32) NOT NULL DEFAULT 'WARN',
	last_check_at       TIMESTAMPTZ,
	last_error_code     VARCHAR(64) NOT NULL DEFAULT '',
	last_error_message  TEXT NOT NULL DEFAULT '',
	created_by          UUID REFERENCES users(user_id),
	updated_by          UUID REFERENCES users(user_id),
	created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	PRIMARY KEY (tenant_id, tool_id)
)`)
}

func (h *ToolControlCenterHandler) GetTools(c *gin.Context) {
	tenantID, userID, ok := getTenantAndUser(c)
	if !ok {
		return
	}
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	manifest, err := h.loadManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools manifest", TraceID: traceID})
		return
	}
	if err := h.seedTenantRows(c.Request.Context(), manifest, tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to initialize tools", TraceID: traceID})
		return
	}
	integrationStates, err := h.loadIntegrationStates(c.Request.Context(), manifest, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load integrations", TraceID: traceID})
		return
	}
	toolStates, err := h.loadToolStates(c.Request.Context(), manifest, tenantID, integrationStates)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools", TraceID: traceID})
		return
	}

	items := make([]map[string]any, 0, len(toolStates))
	for _, ts := range toolStates {
		dep := h.resolveToolDependencies(manifest, ts.Manifest.ID)
		items = append(items, map[string]any{
			"id":                   ts.Manifest.ID,
			"name":                 ts.Manifest.Name,
			"category":             ts.Manifest.Category,
			"description":          ts.Manifest.Description,
			"risk_level":           ts.Manifest.RiskLevel,
			"is_enabled":           ts.Enabled,
			"status":               ts.ResolvedStatus,
			"missing_integrations": ts.MissingIntegrations,
			"missing_binaries":     ts.MissingBinaries,
			"last_check_at":        ts.LastCheckAtISO,
			"last_error_code":      ts.LastErrorCode,
			"last_error_message":   ts.LastErrorMessage,
			"dependencies": map[string]any{
				"all_of_integrations": dep.AllOfIntegrations,
				"any_of_integrations": dep.AnyOfIntegrations,
				"binaries":            dep.Binaries,
			},
		})
	}

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: map[string]any{
		"tools":                        items,
		"manifest_path":                h.manifestPath,
		"registered_tool_count":        len(manifest.Tools),
		"registered_integration_count": len(manifest.Integrations),
	}, TraceID: traceID})
}
func (h *ToolControlCenterHandler) GetToolDetail(c *gin.Context) {
	tenantID, userID, ok := getTenantAndUser(c)
	if !ok {
		return
	}
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	toolID := strings.TrimSpace(c.Param("id"))
	if toolID == "" {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid tool id", TraceID: traceID})
		return
	}

	manifest, err := h.loadManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools manifest", TraceID: traceID})
		return
	}
	if err := h.seedTenantRows(c.Request.Context(), manifest, tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to initialize tools", TraceID: traceID})
		return
	}
	integrationStates, err := h.loadIntegrationStates(c.Request.Context(), manifest, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load integrations", TraceID: traceID})
		return
	}
	toolStates, err := h.loadToolStates(c.Request.Context(), manifest, tenantID, integrationStates)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools", TraceID: traceID})
		return
	}

	for _, ts := range toolStates {
		if ts.Manifest.ID != toolID {
			continue
		}
		dep := h.resolveToolDependencies(manifest, ts.Manifest.ID)
		c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: map[string]any{
			"id":                   ts.Manifest.ID,
			"name":                 ts.Manifest.Name,
			"category":             ts.Manifest.Category,
			"description":          ts.Manifest.Description,
			"risk_level":           ts.Manifest.RiskLevel,
			"is_enabled":           ts.Enabled,
			"status":               ts.ResolvedStatus,
			"last_check_at":        ts.LastCheckAtISO,
			"last_error_code":      ts.LastErrorCode,
			"last_error_message":   ts.LastErrorMessage,
			"missing_integrations": ts.MissingIntegrations,
			"missing_binaries":     ts.MissingBinaries,
			"dependencies": map[string]any{
				"all_of_integrations": dep.AllOfIntegrations,
				"any_of_integrations": dep.AnyOfIntegrations,
				"binaries":            dep.Binaries,
			},
		}, TraceID: traceID})
		return
	}

	c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "tool not found", TraceID: traceID})
}

func (h *ToolControlCenterHandler) ToggleTool(c *gin.Context) {
	tenantID, userID, ok := getTenantAndUser(c)
	if !ok {
		return
	}
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	toolID := strings.TrimSpace(c.Param("id"))
	if toolID == "" {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid tool id", TraceID: traceID})
		return
	}

	var req toggleToolRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid request: " + err.Error(), TraceID: traceID})
		return
	}

	manifest, err := h.loadManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools manifest", TraceID: traceID})
		return
	}
	if err := h.seedTenantRows(c.Request.Context(), manifest, tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to initialize tools", TraceID: traceID})
		return
	}

	status := statusWarn
	if !req.Enabled {
		status = statusDisabled
	}
	_, err = h.db.Exec(c.Request.Context(), `
UPDATE tool_status
   SET is_enabled = $1,
       status = $2,
       updated_by = $3,
       updated_at = NOW()
 WHERE tenant_id = $4 AND tool_id = $5`,
		req.Enabled, status, userID, tenantID, toolID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to update tool status", TraceID: traceID})
		return
	}
	h.writeAudit(c.Request.Context(), tenantID, userID, traceID, "admin.tools.toggle", map[string]any{"tool_id": toolID, "is_enabled": req.Enabled})
	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "tool status updated", Data: map[string]any{"tool_id": toolID, "is_enabled": req.Enabled}, TraceID: traceID})
}

func (h *ToolControlCenterHandler) ListIntegrations(c *gin.Context) {
	tenantID, userID, ok := getTenantAndUser(c)
	if !ok {
		return
	}
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	manifest, err := h.loadManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools manifest", TraceID: traceID})
		return
	}
	if err := h.seedTenantRows(c.Request.Context(), manifest, tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to initialize integrations", TraceID: traceID})
		return
	}
	integrationStates, err := h.loadIntegrationStates(c.Request.Context(), manifest, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load integrations", TraceID: traceID})
		return
	}

	items := make([]map[string]any, 0, len(integrationStates))
	for _, st := range integrationStates {
		lastCheckAt := ""
		if st.Row.LastCheckAt != nil {
			lastCheckAt = st.Row.LastCheckAt.UTC().Format(time.RFC3339)
		}
		items = append(items, map[string]any{
			"id":                 st.Manifest.ID,
			"type":               st.Manifest.Type,
			"display_name":       st.Row.DisplayName,
			"category":           st.Manifest.Category,
			"description":        st.Manifest.Description,
			"required_fields":    st.Manifest.RequiredFields,
			"optional_fields":    st.Manifest.OptionalFields,
			"field_specs":        normalizeFieldSpecs(st.Manifest),
			"missing_fields":     st.MissingFields,
			"is_enabled":         st.Row.IsEnabled,
			"status":             st.Row.Status,
			"last_check_at":      lastCheckAt,
			"last_error_code":    st.Row.LastErrorCode,
			"last_error_message": st.Row.LastErrorMessage,
			"mandatory":          st.Manifest.Mandatory,
			"check_type":         st.Manifest.CheckType,
			"configured":         st.MaskedConfigured,
		})
	}

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: map[string]any{"integrations": items}, TraceID: traceID})
}
func (h *ToolControlCenterHandler) GetIntegrationDetail(c *gin.Context) {
	tenantID, userID, ok := getTenantAndUser(c)
	if !ok {
		return
	}
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	integrationID := strings.TrimSpace(c.Param("id"))
	if integrationID == "" {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid integration id", TraceID: traceID})
		return
	}

	manifest, err := h.loadManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools manifest", TraceID: traceID})
		return
	}
	if err := h.seedTenantRows(c.Request.Context(), manifest, tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to initialize integrations", TraceID: traceID})
		return
	}
	states, err := h.loadIntegrationStates(c.Request.Context(), manifest, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load integrations", TraceID: traceID})
		return
	}

	for _, st := range states {
		if st.Manifest.ID != integrationID {
			continue
		}
		lastCheckAt := ""
		if st.Row.LastCheckAt != nil {
			lastCheckAt = st.Row.LastCheckAt.UTC().Format(time.RFC3339)
		}
		c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: map[string]any{
			"id":                 st.Manifest.ID,
			"type":               st.Manifest.Type,
			"display_name":       st.Row.DisplayName,
			"category":           st.Manifest.Category,
			"description":        st.Manifest.Description,
			"required_fields":    st.Manifest.RequiredFields,
			"optional_fields":    st.Manifest.OptionalFields,
			"field_specs":        normalizeFieldSpecs(st.Manifest),
			"missing_fields":     st.MissingFields,
			"is_enabled":         st.Row.IsEnabled,
			"status":             st.Row.Status,
			"last_check_at":      lastCheckAt,
			"last_error_code":    st.Row.LastErrorCode,
			"last_error_message": st.Row.LastErrorMessage,
			"mandatory":          st.Manifest.Mandatory,
			"check_type":         st.Manifest.CheckType,
			"configured":         st.MaskedConfigured,
		}, TraceID: traceID})
		return
	}
	c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "integration not found", TraceID: traceID})
}

func (h *ToolControlCenterHandler) UpdateIntegrationSecret(c *gin.Context) {
	tenantID, userID, ok := getTenantAndUser(c)
	if !ok {
		return
	}
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	integrationID := strings.TrimSpace(c.Param("id"))
	if integrationID == "" {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid integration id", TraceID: traceID})
		return
	}

	var req updateIntegrationSecretRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid request: " + err.Error(), TraceID: traceID})
		return
	}

	manifest, err := h.loadManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools manifest", TraceID: traceID})
		return
	}
	if err := h.seedTenantRows(c.Request.Context(), manifest, tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to initialize integrations", TraceID: traceID})
		return
	}
	manifestIt, ok := findManifestIntegration(manifest, integrationID)
	if !ok {
		c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "integration not found in manifest", TraceID: traceID})
		return
	}

	allowed := append([]string{}, manifestIt.RequiredFields...)
	allowed = append(allowed, manifestIt.OptionalFields...)
	if !containsString(allowed, req.SecretKeyName) {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "secret_key_name not allowed for integration", TraceID: traceID})
		return
	}

	ciphertext, err := encryptSecret(req.SecretValue)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to encrypt secret", TraceID: traceID})
		return
	}
	last4 := maskedLast4(req.SecretValue)
	displayName := strings.TrimSpace(req.DisplayName)
	if displayName == "" {
		displayName = manifestIt.DisplayName
	}

	tx, err := h.db.Begin(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to start transaction", TraceID: traceID})
		return
	}
	defer tx.Rollback(c.Request.Context())

	isEnabled := true
	if req.IsEnabled != nil {
		isEnabled = *req.IsEnabled
	}
	_ = tx.QueryRow(c.Request.Context(), `SELECT is_enabled FROM integrations WHERE tenant_id = $1 AND id = $2`, tenantID, integrationID).Scan(&isEnabled)
	if req.IsEnabled != nil {
		isEnabled = *req.IsEnabled
	}

	_, err = tx.Exec(c.Request.Context(), `
INSERT INTO integrations (
	id, tenant_id, type, display_name, is_enabled, status, created_by, updated_by
) VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
ON CONFLICT (tenant_id, id) DO UPDATE SET
	type = EXCLUDED.type,
	display_name = EXCLUDED.display_name,
	is_enabled = EXCLUDED.is_enabled,
	updated_by = EXCLUDED.updated_by,
	updated_at = NOW()`,
		integrationID, tenantID, manifestIt.Type, displayName, isEnabled, statusWarn, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to upsert integration", TraceID: traceID})
		return
	}

	_, err = tx.Exec(c.Request.Context(), `
INSERT INTO integration_secrets (
	integration_id, tenant_id, secret_key_name, secret_ciphertext, secret_last4, rotated_at, rotated_by
) VALUES ($1, $2, $3, $4, $5, NOW(), $6)
ON CONFLICT (tenant_id, integration_id, secret_key_name) DO UPDATE SET
	secret_ciphertext = EXCLUDED.secret_ciphertext,
	secret_last4 = EXCLUDED.secret_last4,
	rotated_at = NOW(),
	rotated_by = EXCLUDED.rotated_by`,
		integrationID, tenantID, req.SecretKeyName, ciphertext, last4, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to store secret", TraceID: traceID})
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to commit secret update", TraceID: traceID})
		return
	}

	h.writeAudit(c.Request.Context(), tenantID, userID, traceID, "admin.integrations.secret.update", map[string]any{
		"integration_id":  integrationID,
		"secret_key_name": req.SecretKeyName,
		"secret_last4":    last4,
	})

	states, err := h.loadIntegrationStates(c.Request.Context(), manifest, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "secret updated but failed to load integration", TraceID: traceID})
		return
	}
	for _, st := range states {
		if st.Manifest.ID == integrationID {
			c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "secret updated", Data: map[string]any{
				"integration_id": integrationID,
				"status":         st.Row.Status,
				"configured":     st.MaskedConfigured,
				"missing_fields": st.MissingFields,
			}, TraceID: traceID})
			return
		}
	}

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "secret updated", Data: map[string]any{"integration_id": integrationID}, TraceID: traceID})
}
func (h *ToolControlCenterHandler) CheckIntegration(c *gin.Context) {
	tenantID, userID, ok := getTenantAndUser(c)
	if !ok {
		return
	}
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	integrationID := strings.TrimSpace(c.Param("id"))
	if integrationID == "" {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid integration id", TraceID: traceID})
		return
	}

	manifest, err := h.loadManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools manifest", TraceID: traceID})
		return
	}
	if err := h.seedTenantRows(c.Request.Context(), manifest, tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to initialize integrations", TraceID: traceID})
		return
	}
	states, err := h.loadIntegrationStates(c.Request.Context(), manifest, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load integrations", TraceID: traceID})
		return
	}

	var target *integrationState
	for i := range states {
		if states[i].Manifest.ID == integrationID {
			target = &states[i]
			break
		}
	}
	if target == nil {
		c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "integration not found", TraceID: traceID})
		return
	}
	if !target.Row.IsEnabled {
		h.updateIntegrationCheckResult(c.Request.Context(), tenantID, integrationID, statusDisabled, "DISABLED_BY_ADMIN", "integration disabled by admin")
		c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "checked", Data: map[string]any{"integration_id": integrationID, "status": statusDisabled}, TraceID: traceID})
		return
	}
	if len(target.MissingFields) > 0 {
		h.updateIntegrationCheckResult(c.Request.Context(), tenantID, integrationID, statusMissingCredentials, "MISSING_FIELDS", "required fields missing")
		c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "checked", Data: map[string]any{
			"integration_id": integrationID,
			"status":         statusMissingCredentials,
			"missing_fields": target.MissingFields,
		}, TraceID: traceID})
		return
	}

	cacheKey := tenantID.String() + "::" + integrationID
	h.checkMu.Lock()
	if entry, ok := h.checkCache[cacheKey]; ok && time.Now().Before(entry.ExpiresAt) {
		h.checkMu.Unlock()
		c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "checked (cached)", Data: map[string]any{
			"integration_id": integrationID,
			"status":         entry.Status,
			"error_code":     entry.ErrorCode,
			"error_message":  entry.ErrorMsg,
			"checked_at":     entry.CheckedAt.UTC().Format(time.RFC3339),
			"cached":         true,
		}, TraceID: traceID})
		return
	}
	h.checkMu.Unlock()

	secrets, err := h.getSecretValues(c.Request.Context(), tenantID, integrationID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to read integration secrets", TraceID: traceID})
		return
	}
	status, errCode, errMsg := runIntegrationHealthCheck(target.Manifest, secrets)
	h.updateIntegrationCheckResult(c.Request.Context(), tenantID, integrationID, status, errCode, errMsg)

	h.checkMu.Lock()
	h.checkCache[cacheKey] = checkCacheEntry{
		Status:    status,
		ErrorCode: errCode,
		ErrorMsg:  errMsg,
		CheckedAt: time.Now().UTC(),
		ExpiresAt: time.Now().UTC().Add(60 * time.Second),
	}
	h.checkMu.Unlock()

	h.writeAudit(c.Request.Context(), tenantID, userID, traceID, "admin.integrations.check", map[string]any{
		"integration_id": integrationID,
		"status":         status,
		"error_code":     errCode,
	})

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "checked", Data: map[string]any{
		"integration_id": integrationID,
		"status":         status,
		"error_code":     errCode,
		"error_message":  errMsg,
		"checked_at":     time.Now().UTC().Format(time.RFC3339),
		"cached":         false,
	}, TraceID: traceID})
}

func (h *ToolControlCenterHandler) GetStatusSummary(c *gin.Context) {
	tenantID, userID, ok := getTenantAndUser(c)
	if !ok {
		return
	}
	if denyIfNotAdmin(c) {
		return
	}
	traceID := c.GetString("trace_id")
	manifest, err := h.loadManifest()
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools manifest", TraceID: traceID})
		return
	}
	if err := h.seedTenantRows(c.Request.Context(), manifest, tenantID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to initialize state", TraceID: traceID})
		return
	}
	integrationStates, err := h.loadIntegrationStates(c.Request.Context(), manifest, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load integrations", TraceID: traceID})
		return
	}
	toolStates, err := h.loadToolStates(c.Request.Context(), manifest, tenantID, integrationStates)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to load tools", TraceID: traceID})
		return
	}

	counts := map[string]int{
		statusOK:                 0,
		statusWarn:               0,
		statusError:              0,
		statusDisabled:           0,
		statusMissingCredentials: 0,
		statusMisconfigured:      0,
	}
	issues := make([]map[string]any, 0)
	for _, it := range integrationStates {
		counts[it.Row.Status]++
		if it.Row.Status != statusOK {
			issues = append(issues, map[string]any{
				"kind":               "integration",
				"id":                 it.Manifest.ID,
				"name":               it.Row.DisplayName,
				"category":           it.Manifest.Category,
				"status":             it.Row.Status,
				"last_error_code":    it.Row.LastErrorCode,
				"last_error_message": it.Row.LastErrorMessage,
				"missing_fields":     it.MissingFields,
			})
		}
	}
	for _, ts := range toolStates {
		counts[ts.ResolvedStatus]++
		if ts.ResolvedStatus != statusOK {
			issues = append(issues, map[string]any{
				"kind":                 "tool",
				"id":                   ts.Manifest.ID,
				"name":                 ts.Manifest.Name,
				"category":             ts.Manifest.Category,
				"status":               ts.ResolvedStatus,
				"last_error_code":      ts.LastErrorCode,
				"last_error_message":   ts.LastErrorMessage,
				"missing_integrations": ts.MissingIntegrations,
				"missing_binaries":     ts.MissingBinaries,
			})
		}
	}

	sort.SliceStable(issues, func(i, j int) bool {
		return severityRank(fmt.Sprint(issues[i]["status"])) < severityRank(fmt.Sprint(issues[j]["status"]))
	})

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: map[string]any{
		"summary": map[string]any{
			"ok":                  counts[statusOK],
			"warn":                counts[statusWarn],
			"error":               counts[statusError],
			"disabled":            counts[statusDisabled],
			"missing_credentials": counts[statusMissingCredentials],
			"misconfigured":       counts[statusMisconfigured],
		},
		"issues": issues,
	}, TraceID: traceID})
}
func (h *ToolControlCenterHandler) loadManifest() (toolManifest, error) {
	b, err := os.ReadFile(h.manifestPath)
	if err != nil {
		return toolManifest{}, err
	}
	b = bytesTrimBOM(b)
	var out toolManifest
	if err := yaml.Unmarshal(b, &out); err != nil {
		return toolManifest{}, err
	}
	return out, nil
}

func (h *ToolControlCenterHandler) seedTenantRows(ctx context.Context, m toolManifest, tenantID, userID uuid.UUID) error {
	for _, it := range m.Integrations {
		enabled := it.DefaultEnabled
		status := statusMissingCredentials
		if !enabled {
			status = statusDisabled
		}
		_, err := h.db.Exec(ctx, `
INSERT INTO integrations (id, tenant_id, type, display_name, is_enabled, status, created_by, updated_by)
VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
ON CONFLICT (tenant_id, id) DO NOTHING`, it.ID, tenantID, it.Type, it.DisplayName, enabled, status, userID)
		if err != nil {
			return err
		}
	}
	for _, t := range m.Tools {
		enabled := t.DefaultEnabled
		status := statusWarn
		if !enabled {
			status = statusDisabled
		}
		_, err := h.db.Exec(ctx, `
INSERT INTO tool_status (tool_id, tenant_id, is_enabled, status, created_by, updated_by)
VALUES ($1, $2, $3, $4, $5, $5)
ON CONFLICT (tenant_id, tool_id) DO NOTHING`, t.ID, tenantID, enabled, status, userID)
		if err != nil {
			return err
		}
	}
	return nil
}

func (h *ToolControlCenterHandler) loadIntegrationStates(ctx context.Context, m toolManifest, tenantID uuid.UUID) ([]integrationState, error) {
	rows, err := h.db.Query(ctx, `
SELECT id, type, display_name, is_enabled, status, last_check_at, last_error_code, last_error_message
  FROM integrations
 WHERE tenant_id = $1`, tenantID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	rowMap := map[string]integrationRow{}
	for rows.Next() {
		var row integrationRow
		if err := rows.Scan(&row.ID, &row.Type, &row.DisplayName, &row.IsEnabled, &row.Status, &row.LastCheckAt, &row.LastErrorCode, &row.LastErrorMessage); err != nil {
			return nil, err
		}
		rowMap[row.ID] = row
	}

	secretFieldSet, err := h.getSecretFieldSetByIntegration(ctx, tenantID)
	if err != nil {
		return nil, err
	}

	states := make([]integrationState, 0, len(m.Integrations))
	for _, mit := range m.Integrations {
		row, ok := rowMap[mit.ID]
		if !ok {
			row = integrationRow{ID: mit.ID, Type: mit.Type, DisplayName: mit.DisplayName, IsEnabled: mit.DefaultEnabled, Status: statusMissingCredentials}
		}
		provided := secretFieldSet[mit.ID]
		missingFields := make([]string, 0)
		for _, field := range mit.RequiredFields {
			if !provided[field] {
				missingFields = append(missingFields, field)
			}
		}
		resolvedStatus := row.Status
		if !row.IsEnabled {
			resolvedStatus = statusDisabled
		} else if len(missingFields) > 0 {
			resolvedStatus = statusMissingCredentials
			row.LastErrorCode = "MISSING_FIELDS"
			row.LastErrorMessage = "required fields missing"
		} else if resolvedStatus == "" {
			resolvedStatus = statusWarn
		}
		_, _ = h.db.Exec(ctx, `UPDATE integrations SET status = $1, updated_at = NOW() WHERE tenant_id = $2 AND id = $3`, resolvedStatus, tenantID, mit.ID)
		row.Status = resolvedStatus
		states = append(states, integrationState{Manifest: mit, Row: row, MissingFields: missingFields, MaskedConfigured: len(missingFields) == 0 && row.IsEnabled})
	}

	sort.Slice(states, func(i, j int) bool {
		return strings.ToLower(states[i].Manifest.DisplayName) < strings.ToLower(states[j].Manifest.DisplayName)
	})
	return states, nil
}

func (h *ToolControlCenterHandler) loadToolStates(ctx context.Context, m toolManifest, tenantID uuid.UUID, integrations []integrationState) ([]toolState, error) {
	rows, err := h.db.Query(ctx, `
SELECT tool_id, is_enabled, status, last_check_at, last_error_code, last_error_message
  FROM tool_status
 WHERE tenant_id = $1`, tenantID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	rowMap := map[string]toolRow{}
	for rows.Next() {
		var row toolRow
		if err := rows.Scan(&row.ToolID, &row.IsEnabled, &row.Status, &row.LastCheckAt, &row.LastErrorCode, &row.LastErrorMessage); err != nil {
			return nil, err
		}
		rowMap[row.ToolID] = row
	}

	integrationStatus := map[string]string{}
	for _, it := range integrations {
		integrationStatus[it.Manifest.ID] = it.Row.Status
	}

	states := make([]toolState, 0, len(m.Tools))
	for _, mt := range m.Tools {
		row, ok := rowMap[mt.ID]
		if !ok {
			row = toolRow{ToolID: mt.ID, IsEnabled: mt.DefaultEnabled, Status: statusWarn}
		}
		dep := h.resolveToolDependencies(m, mt.ID)
		missingBin := missingBinaries(dep.Binaries)
		missingInt := missingIntegrations(dep, integrationStatus)

		resolvedStatus := row.Status
		errorCode := row.LastErrorCode
		errorMsg := row.LastErrorMessage
		if !row.IsEnabled {
			resolvedStatus = statusDisabled
			errorCode = "DISABLED_BY_ADMIN"
			errorMsg = "tool disabled by admin"
		} else if len(missingBin) > 0 {
			resolvedStatus = statusMisconfigured
			errorCode = "MISSING_BINARIES"
			errorMsg = "missing runtime binaries"
		} else if len(missingInt) > 0 {
			resolvedStatus = statusMissingCredentials
			errorCode = "MISSING_INTEGRATIONS"
			errorMsg = "integration dependency not ready"
		} else {
			resolvedStatus = statusOK
			errorCode = ""
			errorMsg = ""
		}

		lastCheckAt := ""
		if row.LastCheckAt != nil {
			lastCheckAt = row.LastCheckAt.UTC().Format(time.RFC3339)
		}
		_, _ = h.db.Exec(ctx, `UPDATE tool_status SET status = $1, last_error_code = $2, last_error_message = $3, updated_at = NOW() WHERE tenant_id = $4 AND tool_id = $5`,
			resolvedStatus, errorCode, errorMsg, tenantID, mt.ID)

		states = append(states, toolState{
			Manifest:            mt,
			Row:                 row,
			ResolvedStatus:      resolvedStatus,
			MissingIntegrations: missingInt,
			MissingBinaries:     missingBin,
			LastErrorCode:       errorCode,
			LastErrorMessage:    errorMsg,
			LastCheckAtISO:      lastCheckAt,
			Enabled:             row.IsEnabled,
		})
	}

	sort.Slice(states, func(i, j int) bool {
		return strings.ToLower(states[i].Manifest.Name) < strings.ToLower(states[j].Manifest.Name)
	})
	return states, nil
}
func (h *ToolControlCenterHandler) resolveToolDependencies(m toolManifest, toolID string) toolDependencyRule {
	for _, t := range m.Tools {
		if t.ID == toolID {
			return mergeDependencyRule(t.Dependencies, m.DependencyMap[toolID])
		}
	}
	return m.DependencyMap[toolID]
}

func mergeDependencyRule(a, b toolDependencyRule) toolDependencyRule {
	all := append([]string{}, a.AllOfIntegrations...)
	for _, item := range b.AllOfIntegrations {
		if !containsString(all, item) {
			all = append(all, item)
		}
	}
	any := append([]string{}, a.AnyOfIntegrations...)
	for _, item := range b.AnyOfIntegrations {
		if !containsString(any, item) {
			any = append(any, item)
		}
	}
	bins := append([]string{}, a.Binaries...)
	for _, item := range b.Binaries {
		if !containsString(bins, item) {
			bins = append(bins, item)
		}
	}
	return toolDependencyRule{AllOfIntegrations: all, AnyOfIntegrations: any, Binaries: bins}
}

func (h *ToolControlCenterHandler) getSecretFieldSetByIntegration(ctx context.Context, tenantID uuid.UUID) (map[string]map[string]bool, error) {
	rows, err := h.db.Query(ctx, `SELECT integration_id, secret_key_name FROM integration_secrets WHERE tenant_id = $1`, tenantID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]map[string]bool{}
	for rows.Next() {
		var integrationID, field string
		if err := rows.Scan(&integrationID, &field); err != nil {
			return nil, err
		}
		if _, ok := out[integrationID]; !ok {
			out[integrationID] = map[string]bool{}
		}
		out[integrationID][field] = true
	}
	return out, nil
}

func (h *ToolControlCenterHandler) getSecretValues(ctx context.Context, tenantID uuid.UUID, integrationID string) (map[string]string, error) {
	rows, err := h.db.Query(ctx, `SELECT secret_key_name, secret_ciphertext FROM integration_secrets WHERE tenant_id = $1 AND integration_id = $2`, tenantID, integrationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var name, ciphertext string
		if err := rows.Scan(&name, &ciphertext); err != nil {
			return nil, err
		}
		plain, err := decryptSecret(ciphertext)
		if err != nil {
			continue
		}
		out[name] = plain
	}
	return out, nil
}

func (h *ToolControlCenterHandler) updateIntegrationCheckResult(ctx context.Context, tenantID uuid.UUID, integrationID, status, errCode, errMsg string) {
	_, _ = h.db.Exec(ctx, `
UPDATE integrations
   SET status = $1,
       last_check_at = NOW(),
       last_error_code = $2,
       last_error_message = $3,
       updated_at = NOW()
 WHERE tenant_id = $4 AND id = $5`, status, errCode, errMsg, tenantID, integrationID)
}

func getTenantAndUser(c *gin.Context) (tenantID uuid.UUID, userID uuid.UUID, ok bool) {
	traceID := c.GetString("trace_id")
	tenantRaw := c.GetString("tenant_id")
	userRaw := c.GetString("user_id")
	if tenantRaw == "" || userRaw == "" {
		c.JSON(http.StatusUnauthorized, models.APIResponse{Code: 0, Msg: "unauthorized", TraceID: traceID})
		return uuid.Nil, uuid.Nil, false
	}
	tid, err := uuid.Parse(tenantRaw)
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid tenant id", TraceID: traceID})
		return uuid.Nil, uuid.Nil, false
	}
	uid, err := uuid.Parse(userRaw)
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid user id", TraceID: traceID})
		return uuid.Nil, uuid.Nil, false
	}
	return tid, uid, true
}

func findManifestIntegration(m toolManifest, integrationID string) (integrationManifestItem, bool) {
	for _, it := range m.Integrations {
		if it.ID == integrationID {
			return it, true
		}
	}
	return integrationManifestItem{}, false
}

func normalizeFieldSpecs(it integrationManifestItem) []map[string]any {
	known := map[string]integrationFieldSpec{}
	for _, fs := range it.FieldSpecs {
		name := strings.TrimSpace(fs.Name)
		if name == "" {
			continue
		}
		known[name] = fs
	}
	ordered := make([]map[string]any, 0, len(it.RequiredFields)+len(it.OptionalFields))
	build := func(name string, required bool) {
		name = strings.TrimSpace(name)
		if name == "" {
			return
		}
		fs, ok := known[name]
		if !ok {
			fs = integrationFieldSpec{
				Name:        name,
				Label:       name,
				Description: "配置项",
				AcquireHint: "请从该服务提供商控制台获取并填入",
				Sensitive:   true,
			}
		}
		label := strings.TrimSpace(fs.Label)
		if label == "" {
			label = name
		}
		ordered = append(ordered, map[string]any{
			"name":         name,
			"label":        label,
			"description":  strings.TrimSpace(fs.Description),
			"acquire_hint": strings.TrimSpace(fs.AcquireHint),
			"example":      strings.TrimSpace(fs.Example),
			"sensitive":    fs.Sensitive,
			"required":     required,
		})
	}
	for _, name := range it.RequiredFields {
		build(name, true)
	}
	for _, name := range it.OptionalFields {
		if containsString(it.RequiredFields, name) {
			continue
		}
		build(name, false)
	}
	return ordered
}

func missingBinaries(bins []string) []string {
	miss := make([]string, 0)
	for _, b := range bins {
		if strings.TrimSpace(b) == "" {
			continue
		}
		if _, err := exec.LookPath(b); err != nil {
			miss = append(miss, b)
		}
	}
	return miss
}

func missingIntegrations(dep toolDependencyRule, integrationStatus map[string]string) []string {
	miss := make([]string, 0)
	for _, iid := range dep.AllOfIntegrations {
		s := integrationStatus[iid]
		if s != statusOK && s != statusWarn {
			miss = append(miss, iid)
		}
	}
	if len(dep.AnyOfIntegrations) > 0 {
		anyOK := false
		for _, iid := range dep.AnyOfIntegrations {
			s := integrationStatus[iid]
			if s == statusOK || s == statusWarn {
				anyOK = true
				break
			}
		}
		if !anyOK {
			miss = append(miss, dep.AnyOfIntegrations...)
		}
	}
	uniq := make([]string, 0, len(miss))
	for _, v := range miss {
		if !containsString(uniq, v) {
			uniq = append(uniq, v)
		}
	}
	return uniq
}

func maskedLast4(value string) string {
	trimmed := strings.TrimSpace(value)
	if len(trimmed) <= 4 {
		return trimmed
	}
	return trimmed[len(trimmed)-4:]
}
func deriveMasterKey() ([]byte, error) {
	raw := strings.TrimSpace(os.Getenv("MASTER_KEY"))
	if raw == "" {
		return nil, errors.New("MASTER_KEY is required")
	}
	if decoded, err := base64.StdEncoding.DecodeString(raw); err == nil && len(decoded) == 32 {
		return decoded, nil
	}
	sum := sha256.Sum256([]byte(raw))
	return sum[:], nil
}

func encryptSecret(plain string) (string, error) {
	key, err := deriveMasterKey()
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	ciphertext := aead.Seal(nil, nonce, []byte(plain), nil)
	payload := append(nonce, ciphertext...)
	return base64.StdEncoding.EncodeToString(payload), nil
}

func decryptSecret(ciphertext string) (string, error) {
	key, err := deriveMasterKey()
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	raw, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", err
	}
	nonceSize := aead.NonceSize()
	if len(raw) < nonceSize {
		return "", errors.New("invalid cipher payload")
	}
	nonce := raw[:nonceSize]
	enc := raw[nonceSize:]
	plain, err := aead.Open(nil, nonce, enc, nil)
	if err != nil {
		return "", err
	}
	return string(plain), nil
}

func runIntegrationHealthCheck(manifest integrationManifestItem, secrets map[string]string) (status, errCode, errMsg string) {
	switch manifest.CheckType {
	case "llm_openai":
		apiKey := strings.TrimSpace(secrets["OPENAI_API_KEY"])
		if apiKey == "" {
			return statusMissingCredentials, "MISSING_OPENAI_API_KEY", "required field missing"
		}
		if !strings.HasPrefix(apiKey, "sk-") {
			return statusMisconfigured, "INVALID_OPENAI_KEY_FORMAT", "api key format invalid"
		}
		req, _ := http.NewRequest(http.MethodGet, "https://api.openai.com/v1/models", nil)
		req.Header.Set("Authorization", "Bearer "+apiKey)
		resp, err := httpClient().Do(req)
		if err != nil {
			return statusError, "OPENAI_CONNECT_FAILED", "failed to connect openai"
		}
		defer resp.Body.Close()
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			return statusOK, "", ""
		}
		if resp.StatusCode == 401 || resp.StatusCode == 403 {
			return statusError, "OPENAI_AUTH_FAILED", "openai auth failed"
		}
		return statusError, "OPENAI_HTTP_ERROR", fmt.Sprintf("openai check failed: %d", resp.StatusCode)
	case "web_search_brave":
		token := strings.TrimSpace(secrets["BRAVE_API_KEY"])
		if token == "" {
			return statusMissingCredentials, "MISSING_BRAVE_API_KEY", "required field missing"
		}
		if len(token) < 20 {
			return statusMisconfigured, "INVALID_BRAVE_KEY_FORMAT", "api key format invalid"
		}
		req, _ := http.NewRequest(http.MethodGet, "https://api.search.brave.com/res/v1/web/search?q=test&count=1", nil)
		req.Header.Set("X-Subscription-Token", token)
		resp, err := httpClient().Do(req)
		if err != nil {
			return statusError, "BRAVE_CONNECT_FAILED", "failed to connect brave"
		}
		defer resp.Body.Close()
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			return statusOK, "", ""
		}
		if resp.StatusCode == 401 || resp.StatusCode == 403 {
			return statusError, "BRAVE_AUTH_FAILED", "brave auth failed"
		}
		return statusError, "BRAVE_HTTP_ERROR", fmt.Sprintf("brave check failed: %d", resp.StatusCode)
	case "channel_slack":
		token := strings.TrimSpace(secrets["SLACK_BOT_TOKEN"])
		if token == "" {
			return statusMissingCredentials, "MISSING_SLACK_BOT_TOKEN", "required field missing"
		}
		req, _ := http.NewRequest(http.MethodGet, "https://slack.com/api/auth.test", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		resp, err := httpClient().Do(req)
		if err != nil {
			return statusError, "SLACK_CONNECT_FAILED", "failed to connect slack"
		}
		defer resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return statusError, "SLACK_HTTP_ERROR", fmt.Sprintf("slack check failed: %d", resp.StatusCode)
		}
		var payload map[string]any
		_ = json.NewDecoder(resp.Body).Decode(&payload)
		if ok, _ := payload["ok"].(bool); ok {
			return statusOK, "", ""
		}
		return statusError, "SLACK_AUTH_FAILED", "slack auth failed"
	case "channel_webhook":
		hook := strings.TrimSpace(secrets["WEBHOOK_URL"])
		if hook == "" {
			return statusMissingCredentials, "MISSING_WEBHOOK_URL", "required field missing"
		}
		if !(strings.HasPrefix(hook, "http://") || strings.HasPrefix(hook, "https://")) {
			return statusMisconfigured, "INVALID_WEBHOOK_URL", "webhook url invalid"
		}
		return statusOK, "", ""
	case "task_api":
		baseURL := strings.TrimSpace(secrets["TASK_API_BASE_URL"])
		token := strings.TrimSpace(secrets["TASK_API_TOKEN"])
		if baseURL == "" || token == "" {
			return statusMissingCredentials, "MISSING_TASK_API_FIELDS", "required fields missing"
		}
		if !(strings.HasPrefix(baseURL, "http://") || strings.HasPrefix(baseURL, "https://")) {
			return statusMisconfigured, "INVALID_TASK_API_BASE_URL", "task api base url invalid"
		}
		return statusOK, "", ""
	case "ocr_api":
		baseURL := strings.TrimSpace(secrets["OCR_API_BASE_URL"])
		if baseURL == "" {
			return statusMissingCredentials, "MISSING_OCR_API_BASE_URL", "required field missing"
		}
		if !(strings.HasPrefix(baseURL, "http://") || strings.HasPrefix(baseURL, "https://")) {
			return statusMisconfigured, "INVALID_OCR_API_BASE_URL", "ocr api base url invalid"
		}
		return statusOK, "", ""
	case "asr_api":
		baseURL := strings.TrimSpace(secrets["ASR_API_BASE_URL"])
		token := strings.TrimSpace(secrets["ASR_API_TOKEN"])
		if baseURL == "" || token == "" {
			return statusMissingCredentials, "MISSING_ASR_API_FIELDS", "required fields missing"
		}
		if !(strings.HasPrefix(baseURL, "http://") || strings.HasPrefix(baseURL, "https://")) {
			return statusMisconfigured, "INVALID_ASR_API_BASE_URL", "asr api base url invalid"
		}
		return statusOK, "", ""
	case "tts_api":
		baseURL := strings.TrimSpace(secrets["TTS_API_BASE_URL"])
		if baseURL == "" {
			return statusMissingCredentials, "MISSING_TTS_API_BASE_URL", "required field missing"
		}
		if !(strings.HasPrefix(baseURL, "http://") || strings.HasPrefix(baseURL, "https://")) {
			return statusMisconfigured, "INVALID_TTS_API_BASE_URL", "tts api base url invalid"
		}
		return statusOK, "", ""
	default:
		return statusWarn, "CHECK_NOT_IMPLEMENTED", "check type not implemented"
	}
}

func httpClient() *http.Client {
	return &http.Client{Timeout: 4 * time.Second}
}

func severityRank(status string) int {
	switch status {
	case statusError:
		return 0
	case statusMisconfigured:
		return 1
	case statusMissingCredentials:
		return 2
	case statusWarn:
		return 3
	case statusDisabled:
		return 4
	case statusOK:
		return 5
	default:
		return 6
	}
}

func (h *ToolControlCenterHandler) writeAudit(ctx context.Context, tenantID, userID uuid.UUID, traceID, action string, payload map[string]any) {
	body, _ := json.Marshal(payload)
	_, _ = h.db.Exec(ctx, `
INSERT INTO audit_logs (
	tenant_id, user_id, ts, prompt_snapshot, response_snapshot, model_used,
	tokens_in, tokens_out, cost, tools_called, trace_id, fallback_used, skills_used
) VALUES ($1, $2, NOW(), $3, '', 'admin.config_center', 0, 0, 0, '[]'::jsonb, $4, false, '[]'::jsonb)`,
		tenantID, userID, action+":"+string(body), traceID,
	)
}
