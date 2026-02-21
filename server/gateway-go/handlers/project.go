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

type ProjectHandler struct {
	db *pgxpool.Pool
}

func NewProjectHandler(db *pgxpool.Pool) *ProjectHandler {
	h := &ProjectHandler{db: db}
	h.ensureSchema()
	return h
}

func (h *ProjectHandler) ensureSchema() {
	_, _ = h.db.Exec(context.Background(), `
CREATE TABLE IF NOT EXISTS projects (
	project_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	tenant_id     UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
	user_id       UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
	name          VARCHAR(200) NOT NULL,
	description   TEXT NOT NULL DEFAULT '',
	status        VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'deleted')),
	is_temporary  BOOLEAN NOT NULL DEFAULT false,
	created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`)
	_, _ = h.db.Exec(context.Background(), `
CREATE TABLE IF NOT EXISTS project_sources (
	source_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
	project_id     UUID NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
	tenant_id      UUID NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
	user_id        UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
	source_type    VARCHAR(20) NOT NULL CHECK (source_type IN ('text', 'file', 'image', 'audio', 'link')),
	name           VARCHAR(300) NOT NULL,
	content_text   TEXT NOT NULL DEFAULT '',
	file_path      TEXT NOT NULL DEFAULT '',
	link_url       TEXT NOT NULL DEFAULT '',
	metadata       JSONB NOT NULL DEFAULT '{}',
	created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`)
}

type createProjectRequest struct {
	Name        string `json:"name" binding:"required,min=1,max=200"`
	Description string `json:"description"`
	IsTemporary bool   `json:"is_temporary"`
}

type createProjectSourceRequest struct {
	SourceID    string         `json:"source_id"`
	SourceType  string         `json:"source_type" binding:"required,oneof=text file image audio link"`
	Name        string         `json:"name" binding:"required,min=1,max=300"`
	ContentText string         `json:"content_text"`
	FilePath    string         `json:"file_path"`
	LinkURL     string         `json:"link_url"`
	Metadata    map[string]any `json:"metadata"`
}

func (h *ProjectHandler) List(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")

	rows, err := h.db.Query(context.Background(),
		`SELECT project_id, name, description, status, is_temporary, created_at, updated_at
		   FROM projects
		  WHERE user_id = $1 AND status <> 'deleted'
		  ORDER BY updated_at DESC`,
		userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to query projects", TraceID: traceID})
		return
	}
	defer rows.Close()

	items := make([]models.ProjectItem, 0)
	for rows.Next() {
		var (
			pid       uuid.UUID
			item      models.ProjectItem
			createdAt time.Time
			updatedAt time.Time
		)
		if err := rows.Scan(&pid, &item.Name, &item.Description, &item.Status, &item.IsTemporary, &createdAt, &updatedAt); err != nil {
			continue
		}
		item.ProjectID = pid.String()
		item.CreatedAt = createdAt.Format(time.RFC3339)
		item.UpdatedAt = updatedAt.Format(time.RFC3339)
		items = append(items, item)
	}

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: items, TraceID: traceID})
}

func (h *ProjectHandler) Create(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")

	var req createProjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid request: " + err.Error(), TraceID: traceID})
		return
	}

	projectID := uuid.New()
	_, err := h.db.Exec(context.Background(),
		`INSERT INTO projects (project_id, tenant_id, user_id, name, description, is_temporary)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		projectID, tenantID, userID, req.Name, req.Description, req.IsTemporary,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to create project", TraceID: traceID})
		return
	}

	c.JSON(http.StatusCreated, models.APIResponse{
		Code: 1,
		Msg:  "project created",
		Data: map[string]any{
			"project_id":   projectID.String(),
			"name":         req.Name,
			"description":  req.Description,
			"is_temporary": req.IsTemporary,
		},
		TraceID: traceID,
	})
}

type promoteProjectRequest struct {
	Name        string `json:"name" binding:"required,min=1,max=200"`
	Description string `json:"description"`
}

func (h *ProjectHandler) Promote(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	projectID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid project id", TraceID: traceID})
		return
	}

	var req promoteProjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid request: " + err.Error(), TraceID: traceID})
		return
	}

	tag, err := h.db.Exec(context.Background(),
		`UPDATE projects SET 
		 	is_temporary = false, 
			name = $1, 
			description = $2,
			updated_at = NOW()
		 WHERE project_id = $3 AND user_id = $4 AND is_temporary = true AND status = 'active'`,
		req.Name, req.Description, projectID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to promote project", TraceID: traceID})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "temporary project not found or already promoted", TraceID: traceID})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code: 1,
		Msg:  "project promoted locally",
		Data: map[string]any{
			"project_id": projectID.String(),
			"name":       req.Name,
		},
		TraceID: traceID,
	})
}

// Delete marks a project as deleted (soft delete).
func (h *ProjectHandler) Delete(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")

	projectID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid project id", TraceID: traceID})
		return
	}

	ctx := context.Background()
	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to delete project", TraceID: traceID})
		return
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx,
		`UPDATE projects
		    SET status = 'deleted', updated_at = NOW()
		  WHERE project_id = $1 AND user_id = $2 AND status <> 'deleted'`,
		projectID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to delete project", TraceID: traceID})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "project not found", TraceID: traceID})
		return
	}

	sessionsTag, err := tx.Exec(ctx,
		`DELETE FROM sessions WHERE project_id = $1 AND user_id = $2`,
		projectID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to delete project sessions", TraceID: traceID})
		return
	}

	_, err = tx.Exec(ctx,
		`DELETE FROM project_sources WHERE project_id = $1 AND user_id = $2`,
		projectID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to delete project sources", TraceID: traceID})
		return
	}

	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to finalize project deletion", TraceID: traceID})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code: 1,
		Msg:  "project deleted",
		Data: map[string]any{
			"project_id":       projectID.String(),
			"deleted_sessions": sessionsTag.RowsAffected(),
		},
		TraceID: traceID,
	})
}

func (h *ProjectHandler) ListSources(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	projectID := c.Param("id")

	rows, err := h.db.Query(context.Background(),
		`SELECT source_id, project_id, source_type, name, content_text, file_path, link_url, metadata, created_at
		   FROM project_sources
		  WHERE project_id = $1 AND user_id = $2
		  ORDER BY created_at DESC`,
		projectID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to query project sources", TraceID: traceID})
		return
	}
	defer rows.Close()

	items := make([]models.ProjectSourceItem, 0)
	for rows.Next() {
		var (
			sourceID     uuid.UUID
			pid          uuid.UUID
			item         models.ProjectSourceItem
			metadataRaw  []byte
			createdAtRaw time.Time
		)
		if err := rows.Scan(
			&sourceID,
			&pid,
			&item.SourceType,
			&item.Name,
			&item.ContentText,
			&item.FilePath,
			&item.LinkURL,
			&metadataRaw,
			&createdAtRaw,
		); err != nil {
			continue
		}
		item.SourceID = sourceID.String()
		item.ProjectID = pid.String()
		item.CreatedAt = createdAtRaw.Format(time.RFC3339)
		item.MetadataJSON = string(metadataRaw)
		items = append(items, item)
	}

	c.JSON(http.StatusOK, models.APIResponse{Code: 1, Msg: "ok", Data: items, TraceID: traceID})
}

func (h *ProjectHandler) CreateSource(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")
	projectID := c.Param("id")

	var req createProjectSourceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid request: " + err.Error(), TraceID: traceID})
		return
	}

	var (
		sourceType  = req.SourceType
		name        = req.Name
		contentText = req.ContentText
		filePath    = req.FilePath
		linkURL     = req.LinkURL
	)

	metadata := req.Metadata
	if metadata == nil {
		metadata = map[string]any{}
	}

	if req.SourceID != "" {
		srcID, err := uuid.Parse(req.SourceID)
		if err != nil {
			c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid source_id", TraceID: traceID})
			return
		}
		var rawMeta []byte
		err = h.db.QueryRow(context.Background(),
			`SELECT source_type, name, content_text, file_path, link_url, metadata
			   FROM user_sources
			  WHERE source_id = $1 AND user_id = $2`,
			srcID, userID,
		).Scan(&sourceType, &name, &contentText, &filePath, &linkURL, &rawMeta)
		if err != nil {
			c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "source not found", TraceID: traceID})
			return
		}
		if len(rawMeta) > 0 {
			_ = json.Unmarshal(rawMeta, &metadata)
		}
		metadata["origin_source_id"] = srcID.String()
	} else {
		// Ensure ad-hoc imported source is available in the global source library.
		libraryID := uuid.New()
		metadataJSON, _ := json.Marshal(metadata)
		_, _ = h.db.Exec(context.Background(),
			`INSERT INTO user_sources (
				source_id, tenant_id, user_id, source_type, name, content_text, file_path, link_url, metadata
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)`,
			libraryID, tenantID, userID, sourceType, name, contentText, filePath, linkURL, string(metadataJSON),
		)
		metadata["origin_source_id"] = libraryID.String()
	}

	metadataJSON, _ := json.Marshal(metadata)
	projectSourceID := uuid.New()

	_, err := h.db.Exec(context.Background(),
		`INSERT INTO project_sources (
			source_id, project_id, tenant_id, user_id, source_type, name, content_text, file_path, link_url, metadata
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)`,
		projectSourceID, projectID, tenantID, userID, sourceType, name, contentText, filePath, linkURL, string(metadataJSON),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to create source", TraceID: traceID})
		return
	}

	c.JSON(http.StatusCreated, models.APIResponse{
		Code: 1,
		Msg:  "source created",
		Data: map[string]any{
			"source_id":    projectSourceID.String(),
			"project_id":   projectID,
			"source_type":  sourceType,
			"name":         name,
			"content_text": contentText,
			"file_path":    filePath,
			"link_url":     linkURL,
		},
		TraceID: traceID,
	})
}

func (h *ProjectHandler) DeleteSource(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	projectID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid project id", TraceID: traceID})
		return
	}
	sourceID, err := uuid.Parse(c.Param("source_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{Code: 0, Msg: "invalid source id", TraceID: traceID})
		return
	}

	tag, err := h.db.Exec(context.Background(),
		`DELETE FROM project_sources
		  WHERE project_id = $1 AND source_id = $2 AND user_id = $3`,
		projectID, sourceID, userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{Code: 0, Msg: "failed to delete project source", TraceID: traceID})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, models.APIResponse{Code: 0, Msg: "project source not found", TraceID: traceID})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code: 1,
		Msg:  "project source deleted",
		Data: map[string]any{
			"project_id": projectID.String(),
			"source_id":  sourceID.String(),
		},
		TraceID: traceID,
	})
}
