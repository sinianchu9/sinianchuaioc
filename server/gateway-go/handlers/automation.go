package handlers

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/aioc/gateway/models"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shopspring/decimal"
)

type AutomationHandler struct {
	db      *pgxpool.Pool
	coreURL string
}

func NewAutomationHandler(db *pgxpool.Pool, coreURL string) *AutomationHandler {
	return &AutomationHandler{db: db, coreURL: strings.TrimRight(coreURL, "/")}
}

func (h *AutomationHandler) List(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")

	rows, err := h.db.Query(context.Background(),
		`SELECT automation_id, name, prompt, skills, schedule_kind, interval_hours, timezone,
		        status, run_immediately, created_at, updated_at
		   FROM automations
		  WHERE user_id = $1 AND tenant_id = $2 AND status != 'deleted'
		  ORDER BY updated_at DESC`,
		userID, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to query automations",
			TraceID: traceID,
		})
		return
	}
	defer rows.Close()

	var out []models.AutomationItem
	for rows.Next() {
		var item models.AutomationItem
		var aid uuid.UUID
		var skillsRaw []byte
		var createdAt, updatedAt interface{ String() string }
		if scanErr := rows.Scan(
			&aid,
			&item.Name,
			&item.Prompt,
			&skillsRaw,
			&item.ScheduleKind,
			&item.IntervalHours,
			&item.Timezone,
			&item.Status,
			&item.RunImmediately,
			&createdAt,
			&updatedAt,
		); scanErr != nil {
			continue
		}
		item.AutomationID = aid.String()
		item.CreatedAt = createdAt.String()
		item.UpdatedAt = updatedAt.String()
		_ = json.Unmarshal(skillsRaw, &item.Skills)
		out = append(out, item)
	}

	if out == nil {
		out = []models.AutomationItem{}
	}
	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "ok",
		Data:    out,
		TraceID: traceID,
	})
}

func (h *AutomationHandler) ListRuns(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")
	automationID := c.Param("id")
	limit := 20

	rows, err := h.db.Query(context.Background(),
		`SELECT run_id, automation_id, status, started_at, finished_at, response_preview,
		        tokens_in, tokens_out, cost, request_id, error_message
		   FROM automation_runs
		  WHERE automation_id = $1 AND user_id = $2 AND tenant_id = $3
		  ORDER BY started_at DESC
		  LIMIT $4`,
		automationID, userID, tenantID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to query automation runs",
			TraceID: traceID,
		})
		return
	}
	defer rows.Close()

	var out []models.AutomationRunItem
	for rows.Next() {
		var item models.AutomationRunItem
		var runID, aid uuid.UUID
		var startedAt interface{ String() string }
		var finishedAt *time.Time
		var cost decimal.Decimal
		var reqID *uuid.UUID
		if scanErr := rows.Scan(
			&runID, &aid, &item.Status, &startedAt, &finishedAt,
			&item.ResponsePreview, &item.TokensIn, &item.TokensOut, &cost, &reqID, &item.ErrorMessage,
		); scanErr != nil {
			continue
		}
		item.RunID = runID.String()
		item.AutomationID = aid.String()
		item.StartedAt = startedAt.String()
		item.Cost = cost.StringFixed(6)
		if finishedAt != nil {
			item.FinishedAt = finishedAt.Format(time.RFC3339)
		}
		if reqID != nil {
			item.RequestID = reqID.String()
		}
		out = append(out, item)
	}
	if out == nil {
		out = []models.AutomationRunItem{}
	}
	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "ok",
		Data:    out,
		TraceID: traceID,
	})
}

func (h *AutomationHandler) Create(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")

	var req models.CreateAutomationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{
			Code:    0,
			Msg:     "invalid request: " + err.Error(),
			TraceID: traceID,
		})
		return
	}

	if req.ScheduleKind == "" {
		req.ScheduleKind = "interval"
	}
	if req.IntervalHours <= 0 {
		req.IntervalHours = 24
	}
	if req.Timezone == "" {
		req.Timezone = "UTC"
	}

	skillsJSON, _ := json.Marshal(req.Skills)
	automationID := uuid.New()

	_, err := h.db.Exec(context.Background(),
		`INSERT INTO automations (
			automation_id, tenant_id, user_id, name, prompt, skills, schedule_kind,
			interval_hours, timezone, run_immediately
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
		automationID, tenantID, userID, req.Name, req.Prompt, string(skillsJSON),
		req.ScheduleKind, req.IntervalHours, req.Timezone, req.RunImmediately,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to create automation",
			TraceID: traceID,
		})
		return
	}

	c.JSON(http.StatusCreated, models.APIResponse{
		Code: 1,
		Msg:  "automation created",
		Data: map[string]any{
			"automation_id": automationID.String(),
		},
		TraceID: traceID,
	})
}

func (h *AutomationHandler) UpdateStatus(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")
	automationID := c.Param("id")

	type statusReq struct {
		Status string `json:"status" binding:"required,oneof=active paused"`
	}
	var req statusReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.APIResponse{
			Code:    0,
			Msg:     "invalid request: " + err.Error(),
			TraceID: traceID,
		})
		return
	}

	result, err := h.db.Exec(context.Background(),
		`UPDATE automations
		    SET status = $1, updated_at = NOW()
		  WHERE automation_id = $2 AND user_id = $3 AND tenant_id = $4 AND status != 'deleted'`,
		req.Status, automationID, userID, tenantID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to update automation status",
			TraceID: traceID,
		})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, models.APIResponse{
			Code:    0,
			Msg:     "automation not found",
			TraceID: traceID,
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "status updated",
		TraceID: traceID,
	})
}

func (h *AutomationHandler) Delete(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")
	automationID := c.Param("id")

	result, err := h.db.Exec(context.Background(),
		`UPDATE automations
		    SET status = 'deleted', updated_at = NOW()
		  WHERE automation_id = $1 AND user_id = $2 AND tenant_id = $3`,
		automationID, userID, tenantID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "failed to delete automation",
			TraceID: traceID,
		})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, models.APIResponse{
			Code:    0,
			Msg:     "automation not found",
			TraceID: traceID,
		})
		return
	}

	c.JSON(http.StatusOK, models.APIResponse{
		Code:    1,
		Msg:     "automation deleted",
		TraceID: traceID,
	})
}

func (h *AutomationHandler) RunNow(c *gin.Context) {
	traceID := c.GetString("trace_id")
	userID := c.GetString("user_id")
	tenantID := c.GetString("tenant_id")
	automationID := c.Param("id")
	planLevel := c.GetString("plan_level")

	var prompt string
	var skillsRaw []byte
	var status string
	err := h.db.QueryRow(context.Background(),
		`SELECT prompt, skills, status
		   FROM automations
		  WHERE automation_id = $1 AND user_id = $2 AND tenant_id = $3`,
		automationID, userID, tenantID,
	).Scan(&prompt, &skillsRaw, &status)
	if err != nil || status == "deleted" {
		c.JSON(http.StatusNotFound, models.APIResponse{
			Code:    0,
			Msg:     "automation not found",
			TraceID: traceID,
		})
		return
	}

	var skills []string
	_ = json.Unmarshal(skillsRaw, &skills)

	runID := uuid.New()
	_, _ = h.db.Exec(context.Background(),
		`INSERT INTO automation_runs (run_id, automation_id, tenant_id, user_id, status, started_at)
		 VALUES ($1,$2,$3,$4,'running',NOW())`,
		runID, automationID, tenantID, userID,
	)

	response, done, execErr := h.executeAutomation(context.Background(), traceID, userID, tenantID, planLevel, prompt, skills)
	if execErr != nil {
		_, _ = h.db.Exec(context.Background(),
			`UPDATE automation_runs
			    SET status='failed', finished_at=NOW(), error_message=$1
			  WHERE run_id=$2`,
			execErr.Error(), runID,
		)
		c.JSON(http.StatusInternalServerError, models.APIResponse{
			Code:    0,
			Msg:     "automation execution failed: " + execErr.Error(),
			TraceID: traceID,
		})
		return
	}

	cost, _ := decimal.NewFromString(fmt.Sprintf("%v", done["cost"]))
	var requestID *uuid.UUID
	if rawReq, ok := done["request_id"].(string); ok {
		if parsed, parseErr := uuid.Parse(rawReq); parseErr == nil {
			requestID = &parsed
		}
	}
	tokensIn := asInt(done["tokens_in"])
	tokensOut := asInt(done["tokens_out"])

	_, _ = h.db.Exec(context.Background(),
		`UPDATE automation_runs
		    SET status='completed', finished_at=NOW(), response_preview=$1,
		        tokens_in=$2, tokens_out=$3, cost=$4, request_id=$5
		  WHERE run_id=$6`,
		truncateForRun(response, 5000), tokensIn, tokensOut, cost, requestID, runID,
	)

	c.JSON(http.StatusOK, models.APIResponse{
		Code: 1,
		Msg:  "automation run completed",
		Data: map[string]any{
			"run_id":         runID.String(),
			"response":       truncateForRun(response, 3000),
			"tokens_in":      tokensIn,
			"tokens_out":     tokensOut,
			"cost":           cost.StringFixed(6),
			"request_id":     done["request_id"],
			"skills_applied": skills,
		},
		TraceID: traceID,
	})
}

func (h *AutomationHandler) executeAutomation(
	ctx context.Context,
	traceID, userID, tenantID, planLevel, prompt string,
	skills []string,
) (string, map[string]any, error) {
	payload := map[string]any{
		"mode":   "economy",
		"skills": skills,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
	}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequestWithContext(ctx, "POST", h.coreURL+"/internal/chat/stream", bytes.NewReader(body))
	if err != nil {
		return "", nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("X-Trace-ID", traceID)
	req.Header.Set("X-User-ID", userID)
	req.Header.Set("X-Tenant-ID", tenantID)
	req.Header.Set("X-Plan-Level", planLevel)

	client := &http.Client{Timeout: 90 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		return "", nil, fmt.Errorf("core status=%d body=%s", resp.StatusCode, string(raw))
	}

	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 0, 1024), 1024*1024)
	var currentEvent string
	var full strings.Builder
	doneData := map[string]any{}

	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "event: ") {
			currentEvent = strings.TrimPrefix(line, "event: ")
			continue
		}
		if strings.HasPrefix(line, "data: ") {
			data := strings.TrimPrefix(line, "data: ")
			switch currentEvent {
			case "content":
				full.WriteString(data)
			case "done":
				_ = json.Unmarshal([]byte(data), &doneData)
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return "", nil, err
	}
	if len(doneData) == 0 {
		return "", nil, fmt.Errorf("missing done event from core stream")
	}
	return full.String(), doneData, nil
}

func asInt(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	default:
		return 0
	}
}

func truncateForRun(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "...[truncated]"
}
