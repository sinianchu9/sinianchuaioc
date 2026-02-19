package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type SourceHandler struct {
	db *pgxpool.Pool
}

func NewSourceHandler(db *pgxpool.Pool) *SourceHandler {
	h := &SourceHandler{db: db}
	h.ensureSchema()
	return h
}

func (h *SourceHandler) ensureSchema() {
	_, _ = h.db.Exec(context.Background(), `
CREATE TABLE IF NOT EXISTS user_sources (
	source_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	tenant_id      UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
	user_id        UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
	source_type    VARCHAR(20) NOT NULL CHECK (source_type IN ('text', 'file', 'image', 'audio', 'link')),
	name           VARCHAR(300) NOT NULL,
	content_text   TEXT NOT NULL DEFAULT '',
	file_path      TEXT NOT NULL DEFAULT '',
	link_url       TEXT NOT NULL DEFAULT '',
	metadata       JSONB NOT NULL DEFAULT '{}',
	created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`)
}

type createUserSourceRequest struct {
	SourceType  string         `json:"source_type" binding:"required,oneof=text file image audio link"`
	Name        string         `json:"name" binding:"required,min=1,max=300"`
	ContentText string         `json:"content_text"`
	FilePath    string         `json:"file_path"`
	LinkURL     string         `json:"link_url"`
	Metadata    map[string]any `json:"metadata"`
}

type updateUserSourceRequest struct {
	SourceType  string         `json:"source_type" binding:"required,oneof=text file image audio link"`
	Name        string         `json:"name" binding:"required,min=1,max=300"`
	ContentText string         `json:"content_text"`
	FilePath    string         `json:"file_path"`
	LinkURL     string         `json:"link_url"`
	Metadata    map[string]any `json:"metadata"`
}

func (h *SourceHandler) List(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")

	rows, err := h.db.Query(context.Background(),
		`SELECT source_id, source_type, name, content_text, file_path, link_url, metadata, created_at, updated_at
		   FROM user_sources
		  WHERE user_id = $1
		  ORDER BY updated_at DESC`,
		userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to query sources", TraceID: traceID})
		return
	}
	defer rows.Close()

	items := make([]models.UserSourceItem, 0)
	for rows.Next() {
		var (
			sid         uuid.UUID
			item        models.UserSourceItem
			metadataRaw []byte
			createdAt   time.Time
			updatedAt   time.Time
		)
		if err := rows.Scan(
			&sid,
			&item.SourceType,
			&item.Name,
			&item.ContentText,
			&item.FilePath,
			&item.LinkURL,
			&metadataRaw,
			&createdAt,
			&updatedAt,
		); err != nil {
			continue
		}
		item.SourceID = sid.String()
		item.MetadataJSON = string(metadataRaw)
		item.CreatedAt = createdAt.Format(time.RFC3339)
		item.UpdatedAt = updatedAt.Format(time.RFC3339)
		items = append(items, item)
	}

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: items, TraceID: traceID})
}

func (h *SourceHandler) Create(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")

	var req createUserSourceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid request: " + err.Error(), TraceID: traceID})
		return
	}

	metadataJSON, _ := json.Marshal(req.Metadata)
	sourceID := uuid.New()

	_, err := h.db.Exec(context.Background(),
		`INSERT INTO user_sources (
			source_id, tenant_id, user_id, source_type, name, content_text, file_path, link_url, metadata
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)`,
		sourceID, tenantID, userID, req.SourceType, req.Name, req.ContentText, req.FilePath, req.LinkURL, string(metadataJSON),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to create source", TraceID: traceID})
		return
	}

	c.JSON(http.StatusCreated, models.APIResponse{
		Code: 1,
		Msg:  "source created",
		Data: map[string]any{
			"source_id":    sourceID.String(),
			"source_type":  req.SourceType,
			"name":         req.Name,
			"content_text": req.ContentText,
			"file_path":    req.FilePath,
			"link_url":     req.LinkURL,
		},
		TraceID: traceID,
	})
}

func (h *SourceHandler) Update(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	sourceID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid source id", TraceID: traceID})
		return
	}

	var req updateUserSourceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid request: " + err.Error(), TraceID: traceID})
		return
	}

	metadataJSON, _ := json.Marshal(req.Metadata)
	tag, err := h.db.Exec(context.Background(),
		`UPDATE user_sources
		    SET source_type = $1,
		        name = $2,
		        content_text = $3,
		        file_path = $4,
		        link_url = $5,
		        metadata = $6::jsonb,
		        updated_at = NOW()
		  WHERE source_id = $7 AND user_id = $8`,
		req.SourceType, req.Name, req.ContentText, req.FilePath, req.LinkURL, string(metadataJSON), sourceID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to update source", TraceID: traceID})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "source not found", TraceID: traceID})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "source updated",
		Data:    map[string]any{"source_id": sourceID.String()},
		TraceID: traceID,
	})
}

func (h *SourceHandler) Delete(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	sourceID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid source id", TraceID: traceID})
		return
	}

	tag, err := h.db.Exec(context.Background(),
		`DELETE FROM user_sources WHERE source_id = $1 AND user_id = $2`,
		sourceID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to delete source", TraceID: traceID})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "source not found", TraceID: traceID})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "source deleted",
		Data:    map[string]any{"source_id": sourceID.String()},
		TraceID: traceID,
	})
}
