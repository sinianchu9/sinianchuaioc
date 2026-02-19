package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// SessionHandler handles session-related endpoints
type SessionHandler struct {
	db *pgxpool.Pool
}

// NewSessionHandler creates a new session handler
func NewSessionHandler(db *pgxpool.Pool) *SessionHandler {
	return &SessionHandler{db: db}
}

// List handles GET /api/v1/sessions
func (h *SessionHandler) List(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")

	rows, err := h.db.Query(context.Background(),
		`SELECT session_id, title, model_mode, token_count, created_at, updated_at
		 FROM sessions
		 WHERE user_id = $1
		 ORDER BY updated_at DESC
		 LIMIT 100`,
		userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to query sessions",
			TraceID: traceID,
		})
		return
	}
	defer rows.Close()

	var sessions []models.SessionListItem
	for rows.Next() {
		var s models.SessionListItem
		var sid uuid.UUID
		var createdAt, updatedAt interface{}
		if err := rows.Scan(&sid, &s.Title, &s.ModelMode, &s.TokenCount, &createdAt, &updatedAt); err != nil {
			continue
		}
		s.SessionID = sid.String()
		s.CreatedAt = createdAt.(interface{ String() string }).String()
		s.UpdatedAt = updatedAt.(interface{ String() string }).String()
		sessions = append(sessions, s)
	}

	if sessions == nil {
		sessions = []models.SessionListItem{}
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "ok",
		Data:    sessions,
		TraceID: traceID,
	})
}

// Create handles POST /api/v1/sessions
func (h *SessionHandler) Create(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")

	type CreateReq struct {
		Title     string `json:"title"`
		ModelMode string `json:"model_mode"`
	}

	var req CreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		req.Title = "New Chat"
		req.ModelMode = "economy"
	}

	if req.Title == "" {
		req.Title = "New Chat"
	}
	if req.ModelMode == "" {
		req.ModelMode = "economy"
	}

	sessionID := uuid.New()
	_, err := h.db.Exec(context.Background(),
		`INSERT INTO sessions (session_id, user_id, title, model_mode)
		 VALUES ($1, $2, $3, $4)`,
		sessionID, userID, req.Title, req.ModelMode,
	)

	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to create session",
			TraceID: traceID,
		})
		return
	}

	c.JSON(http.StatusCreated, models.APIResponse{
		Code: 1,
		Msg:  "session created",
		Data: map[string]string{
			"session_id": sessionID.String(),
			"title":      req.Title,
			"model_mode": req.ModelMode,
		},
		TraceID: traceID,
	})
}

// Delete handles DELETE /api/v1/sessions/:id
func (h *SessionHandler) Delete(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	sessionID := c.Param("id")

	result, err := h.db.Exec(context.Background(),
		"DELETE FROM sessions WHERE session_id = $1 AND user_id = $2",
		sessionID, userID,
	)

	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to delete session",
			TraceID: traceID,
		})
		return
	}

	if result.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, models.APIResponse{
			Code:    0,
			Msg:     "session not found",
			TraceID: traceID,
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "session deleted",
		TraceID: traceID,
	})
}

// Get handles GET /api/v1/sessions/:id
func (h *SessionHandler) Get(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	sessionID := c.Param("id")

	var s models.SessionListItem
	var sid uuid.UUID
	var createdAt, updatedAt interface{}
	var messagesJSON []byte

	err := h.db.QueryRow(context.Background(),
		`SELECT session_id, title, model_mode, token_count, created_at, updated_at, messages
		 FROM sessions
		 WHERE session_id = $1 AND user_id = $2`,
		sessionID, userID,
	).Scan(&sid, &s.Title, &s.ModelMode, &s.TokenCount, &createdAt, &updatedAt, &messagesJSON)

	if err != nil {
		c.JSON(http.StatusNotFound, models.APIResponse{
			Code:    0,
			Msg:     "session not found",
			TraceID: traceID,
		})
		return
	}

	s.SessionID = sid.String()
	s.CreatedAt = createdAt.(interface{ String() string }).String()
	s.UpdatedAt = updatedAt.(interface{ String() string }).String()

	// Parse messages if present
	var messages []models.ChatMessage
	if len(messagesJSON) > 0 {
		if err := json.Unmarshal(messagesJSON, &messages); err != nil {
			log.Printf("❌ Failed to unmarshal session messages: %v", err)
		}
	}
	s.Messages = messages

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "ok",
		Data:    s,
		TraceID: traceID,
	})
}
