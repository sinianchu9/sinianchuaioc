package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ClientHandler handles client capability endpoints
type ClientHandler struct {
	db *pgxpool.Pool
}

// NewClientHandler creates a new client handler
func NewClientHandler(db *pgxpool.Pool) *ClientHandler {
	return &ClientHandler{db: db}
}

// Capabilities handles GET /api/v1/client/capabilities
func (h *ClientHandler) Capabilities(c *gin.Context) {
	traceID := c.GetString("trace_id")
	tenantID := c.GetString("tenant_id")

	// Get plan features
	var planLevel string
	err := h.db.QueryRow(context.Background(),
		"SELECT plan_level FROM tenants WHERE tenant_id = $1",
		tenantID,
	).Scan(&planLevel)

	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to query tenant",
			TraceID: traceID,
		})
		return
	}

	// Get plan features from plans table
	var featuresJSON []byte
	err = h.db.QueryRow(context.Background(),
		"SELECT features FROM plans WHERE plan_id = $1",
		planLevel,
	).Scan(&featuresJSON)

	if err != nil {
		// Default capabilities for unknown plans
		c.JSON(http.StatusOK, models.APIResponse{
			Code: 1,
			Msg:  "ok",
			Data: models.ClientCapabilities{
				Chat:        true,
				Stream:      true,
				Tools:       false,
				RAG:         false,
				Models:      []string{"economy"},
				MaxSessions: 5,
				PlanLevel:   planLevel,
			},
			TraceID: traceID,
		})
		return
	}

	// Parse plan features
	var features map[string]any
	if err := json.Unmarshal(featuresJSON, &features); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to parse plan features",
			TraceID: traceID,
		})
		return
	}

	// Build capabilities from plan features
	caps := models.ClientCapabilities{
		PlanLevel: planLevel,
	}

	if v, ok := features["chat"].(bool); ok {
		caps.Chat = v
	}
	if v, ok := features["stream"].(bool); ok {
		caps.Stream = v
	}
	if v, ok := features["tools"].(bool); ok {
		caps.Tools = v
	}
	if v, ok := features["rag"].(bool); ok {
		caps.RAG = v
	}
	if v, ok := features["max_sessions"].(float64); ok {
		caps.MaxSessions = int(v)
	}
	if v, ok := features["models"].([]any); ok {
		for _, m := range v {
			if ms, ok := m.(string); ok {
				caps.Models = append(caps.Models, ms)
			}
		}
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "ok",
		Data:    caps,
		TraceID: traceID,
	})
}
