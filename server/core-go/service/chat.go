package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"path/filepath"
	"strings"
	"time"

	"github.com/aioc/core/engine"
	"github.com/aioc/core/llm"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ChatService handles chat stream orchestration
type ChatService struct {
	router      *llm.Router
	logger      *AuditLogger
	calculator  *CostCalculator
	db          *pgxpool.Pool
	fallbackSec int
	engineReg   *engine.Registry
}

// NewChatService creates a new chat service
func NewChatService(router *llm.Router, logger *AuditLogger, calculator *CostCalculator, db *pgxpool.Pool, fallbackTimeoutSec int, engineReg *engine.Registry) *ChatService {
	return &ChatService{
		router:      router,
		logger:      logger,
		calculator:  calculator,
		db:          db,
		fallbackSec: fallbackTimeoutSec,
		engineReg:   engineReg,
	}
}

// ChatRequest represents an incoming chat request from the gateway
type ChatRequest struct {
	SessionID string        `json:"session_id"`
	Messages  []llm.Message `json:"messages"`
	Mode      string        `json:"mode"`
	Skills    []string      `json:"skills,omitempty"`
	RoleID    string        `json:"role_id,omitempty"`
	TaskID    string        `json:"task_id,omitempty"`
	ProjectID string        `json:"project_id,omitempty"`
	ClientID  string        `json:"client_id"`
}

// StreamResult holds the final result of a streamed chat
type StreamResult struct {
	Model        string
	TokensIn     int
	TokensOut    int
	FallbackUsed bool
	Response     string
}

// StreamChat orchestrates the full chat flow:
// 1. Route to model based on mode
// 2. Call LLM with streaming
// 3. On timeout, fallback to alternate model
// 4. Log billing + audit
// Returns a channel of SSE events
func (s *ChatService) StreamChat(ctx context.Context, req *ChatRequest, traceID, userID, tenantID, planLevel string) (<-chan string, <-chan *StreamResult, error) {
	requestID := uuid.New().String()
	mode := req.Mode
	if mode == "" {
		mode = "economy"
	}

	// Route to primary model
	provider, modelName, maxTokens, err := s.router.Route(mode)
	if err != nil {
		return nil, nil, fmt.Errorf("routing failed: %w", err)
	}

	log.Printf("[%s] Routing to model=%s mode=%s", traceID, modelName, mode)

	// Build LLM request
	llmReq := &llm.ChatRequest{
		Model:     modelName,
		Messages:  ensureIdentity(req.Messages, req.Skills, s.buildExecutionContext(ctx, req, userID)),
		MaxTokens: maxTokens,
		Stream:    true,
	}

	// Sliding window context trimming: keep last N messages to stay within token limits
	if len(llmReq.Messages) > 20 {
		// Keep system message (if any) + last 19 messages
		trimmed := make([]llm.Message, 0, 20)
		if llmReq.Messages[0].Role == "system" {
			trimmed = append(trimmed, llmReq.Messages[0])
			llmReq.Messages = llmReq.Messages[1:]
		}
		start := len(llmReq.Messages) - 19
		if start < 0 {
			start = 0
		}
		trimmed = append(trimmed, llmReq.Messages[start:]...)
		llmReq.Messages = trimmed
		log.Printf("[%s] Trimmed context to %d messages", traceID, len(llmReq.Messages))
	}

	// Create timeout context for fallback
	streamCtx, cancel := context.WithTimeout(ctx, time.Duration(s.fallbackSec)*time.Second)

	sseChan := make(chan string, 128)
	resultChan := make(chan *StreamResult, 1)

	go func() {
		defer cancel()
		defer close(sseChan)
		defer close(resultChan)

		var response strings.Builder
		fallbackUsed := false
		finalModel := modelName
		var tokensIn, tokensOut int
		artifactCandidates := make([]artifactCandidate, 0)

		// Try primary provider
		chunks, err := provider.StreamChat(streamCtx, llmReq)
		if err != nil {
			log.Printf("[%s] Primary provider %s failed: %v, trying fallback", traceID, modelName, err)
			// Try fallback
			fbProvider, fbModel, fbErr := s.router.Fallback(mode)
			if fbErr != nil {
				sseChan <- formatSSE("error", fmt.Sprintf("All providers failed: %v", err))
				return
			}

			llmReq.Model = fbModel
			fallbackUsed = true
			finalModel = fbModel

			fbCtx := context.WithoutCancel(ctx)
			chunks, err = fbProvider.StreamChat(fbCtx, llmReq)
			if err != nil {
				sseChan <- formatSSE("error", fmt.Sprintf("Fallback also failed: %v", err))
				return
			}
		}

		// Stream chunks to SSE
		for chunk := range chunks {
			if chunk.Error != nil {
				log.Printf("[%s] Stream error: %v", traceID, chunk.Error)

				// If primary failed mid-stream, try fallback
				if !fallbackUsed {
					log.Printf("[%s] Attempting mid-stream fallback", traceID)
					fbProvider, fbModel, fbErr := s.router.Fallback(mode)
					if fbErr == nil {
						llmReq.Model = fbModel
						fallbackUsed = true
						finalModel = fbModel
						response.Reset()

						fbChunks, fbErr := fbProvider.StreamChat(ctx, llmReq)
						if fbErr == nil {
							sseChan <- formatSSE("fallback", fbModel)
							for fbChunk := range fbChunks {
								if fbChunk.Error != nil {
									break
								}
								if fbChunk.Content != "" {
									response.WriteString(fbChunk.Content)
									sseChan <- formatSSE("content", fbChunk.Content)
								}
								if fbChunk.Done {
									tokensIn = fbChunk.TokensIn
									tokensOut = fbChunk.TokensOut
								}
							}
						}
					}
				}
				break
			}

			if chunk.Content != "" {
				response.WriteString(chunk.Content)
				sseChan <- formatSSE("content", chunk.Content)
			}

			if chunk.Done {
				tokensIn = chunk.TokensIn
				tokensOut = chunk.TokensOut
				if tokensIn == 0 {
					// Estimate input tokens (~4 chars per token)
					totalInputChars := 0
					for _, m := range req.Messages {
						totalInputChars += len(m.Content)
					}
					tokensIn = totalInputChars / 4
				}
			}
		}

		// Calculate cost
		cost := s.calculator.Calculate(finalModel, tokensIn, tokensOut)

		// Persist usage synchronously to keep billing/accounting consistent.
		var history any
		if req.SessionID != "" {
			history = append(req.Messages, llm.Message{
				Role:    "assistant",
				Content: response.String(),
			})
		}
		entry := &LogEntry{
			TenantID:         tenantID,
			UserID:           userID,
			Model:            finalModel,
			TokensIn:         tokensIn,
			TokensOut:        tokensOut,
			Cost:             cost,
			RequestID:        requestID,
			ClientID:         req.ClientID,
			SessionID:        req.SessionID,
			TraceID:          traceID,
			PromptSnapshot:   formatPromptSnapshot(req.Messages),
			ResponseSnapshot: response.String(),
			SkillsUsed:       req.Skills,
			FallbackUsed:     fallbackUsed,
		}
		if inserted, persistErr := s.logger.CommitUsage(ctx, entry, planLevel, tokensIn+tokensOut, history); persistErr != nil {
			log.Printf("[%s] commit usage failed: %v", traceID, persistErr)
			sseChan <- formatSSE("error", "failed to persist billing and audit logs")
			return
		} else if !inserted {
			log.Printf("[%s] duplicate request_id detected, skipped re-billing request_id=%s", traceID, requestID)
		}
		if err := s.persistProjectArtifacts(ctx, req, tenantID, userID, requestID, artifactCandidates); err != nil {
			log.Printf("[%s] failed to persist project artifacts: %v", traceID, err)
		}

		// Send done event
		doneData := map[string]any{
			"model":         finalModel,
			"tokens_in":     tokensIn,
			"tokens_out":    tokensOut,
			"cost":          cost.StringFixed(6),
			"fallback_used": fallbackUsed,
			"trace_id":      traceID,
			"request_id":    requestID,
		}
		doneJSON, _ := json.Marshal(doneData)
		sseChan <- formatSSE("done", string(doneJSON))

		resultChan <- &StreamResult{
			Model:        finalModel,
			TokensIn:     tokensIn,
			TokensOut:    tokensOut,
			FallbackUsed: fallbackUsed,
			Response:     response.String(),
		}
	}()

	return sseChan, resultChan, nil
}

func formatSSE(event, data string) string {
	return fmt.Sprintf("event: %s\ndata: %s\n\n", event, data)
}

func formatPromptSnapshot(messages []llm.Message) string {
	var sb strings.Builder
	for _, m := range messages {
		sb.WriteString(fmt.Sprintf("[%s]: %s\n", m.Role, truncate(m.Content, 500)))
	}
	return sb.String()
}

// StreamChatViaEngine routes the chat request through the pluggable engine SPI.
// This is the preferred path when ENGINE_PROVIDER is set to a real engine (e.g. "openclaw").
func (s *ChatService) StreamChatViaEngine(ctx context.Context, req *ChatRequest, traceID, userID, tenantID, planLevel string) (<-chan string, <-chan *StreamResult, error) {
	requestID := uuid.New().String()
	mode := req.Mode
	if mode == "" {
		mode = "economy"
	}

	// Get active engine
	eng, err := s.engineReg.Active()
	if err != nil {
		return nil, nil, fmt.Errorf("engine selection failed: %w", err)
	}

	// Route to get model config (for billing purposes and api_key/base_url)
	provider, modelName, _, routeErr := s.router.Route(mode)
	if routeErr != nil {
		return nil, nil, fmt.Errorf("routing failed (engine mode): %w", routeErr)
	}

	apiKey, baseURL := provider.GetConfig()

	// Build engine messages from LLM messages
	finalMsgs := ensureIdentity(req.Messages, req.Skills, s.buildExecutionContext(ctx, req, userID))
	engineMsgs := make([]engine.Message, len(finalMsgs))
	for i, m := range finalMsgs {
		engineMsgs[i] = engine.Message{Role: m.Role, Content: m.Content}
	}

	// Build AgentRequest for the engine
	agentReq := &engine.AgentRequest{
		SessionID: req.SessionID,
		Messages:  engineMsgs,
		Config: engine.ModelConfig{
			ModelName: modelName,
			APIKey:    apiKey,
			BaseURL:   baseURL,
		},
		Skills:         req.Skills,
		RoleID:         req.RoleID,
		TaskID:         req.TaskID,
		ProjectID:      req.ProjectID,
		ProjectSources: s.loadProjectSources(ctx, req.ProjectID, userID),
		AllowedTools:   allowedToolsForPlanAndSkills(planLevel, req.Skills),
		PlanLevel:      planLevel,
		Mode:           mode,
		TraceID:        traceID,
		TenantID:       tenantID,
		UserID:         userID,
		ClientID:       req.ClientID,
	}

	log.Printf("[%s] Engine=%s model=%s mode=%s", traceID, eng.Name(), modelName, mode)

	sseChan := make(chan string, 128)
	resultChan := make(chan *StreamResult, 1)

	go func() {
		defer close(sseChan)
		defer close(resultChan)

		var response strings.Builder
		var tokensIn, tokensOut int
		finalModel := modelName
		artifactCandidates := make([]artifactCandidate, 0, 4)

		// Call engine via SPI
		events, err := eng.StreamExecute(ctx, agentReq)
		if err != nil {
			sseChan <- formatSSE("error", fmt.Sprintf("Engine error: %v", err))
			return
		}

		for event := range events {
			switch event.Type {
			case engine.EventContent:
				if event.Delta != "" {
					response.WriteString(event.Delta)
					sseChan <- formatSSE("content", event.Delta)
				}
			case engine.EventUsage:
				tokensIn = event.TokensIn
				tokensOut = event.TokensOut
			case engine.EventError:
				sseChan <- formatSSE("error", event.Message)
				return
			case engine.EventDone:
				// Will be handled after loop
			case engine.EventUIComponent:
				if event.Component != "" {
					uiData := map[string]any{
						"component": event.Component,
						"args":      event.ComponentArgs,
					}
					uiJSON, _ := json.Marshal(uiData)
					sseChan <- formatSSE("ui_component", string(uiJSON))
				}
			case engine.EventToolCall:
				payload := map[string]any{
					"tool": event.Tool,
					"args": event.Args,
				}
				evJSON, _ := json.Marshal(payload)
				sseChan <- formatSSE("tool_call", string(evJSON))
			case engine.EventToolResult:
				if event.Tool == "artifact_render" || event.Tool == "artifact_bundle_zip" || event.Tool == "tts_synthesize" {
					if cand, ok := parseArtifactCandidate(event.Tool, event.Result); ok {
						artifactCandidates = append(artifactCandidates, cand)
					}
				}
				payload := map[string]any{
					"tool":   event.Tool,
					"result": truncate(event.Result, 2000),
				}
				evJSON, _ := json.Marshal(payload)
				sseChan <- formatSSE("tool_result", string(evJSON))
			}
		}

		// Estimate tokens if engine didn't provide them
		if tokensIn == 0 {
			totalInputChars := 0
			for _, m := range req.Messages {
				totalInputChars += len(m.Content)
			}
			tokensIn = totalInputChars / 4
		}
		if tokensOut == 0 {
			tokensOut = len(response.String()) / 4
		}

		// Calculate cost
		cost := s.calculator.Calculate(finalModel, tokensIn, tokensOut)

		// Persist usage synchronously to keep billing/accounting consistent.
		var history any
		if req.SessionID != "" {
			history = append(req.Messages, llm.Message{
				Role:    "assistant",
				Content: response.String(),
			})
		}
		entry := &LogEntry{
			TenantID:         tenantID,
			UserID:           userID,
			Model:            finalModel,
			TokensIn:         tokensIn,
			TokensOut:        tokensOut,
			Cost:             cost,
			RequestID:        requestID,
			ClientID:         req.ClientID,
			SessionID:        req.SessionID,
			TraceID:          traceID,
			PromptSnapshot:   formatPromptSnapshot(req.Messages),
			ResponseSnapshot: response.String(),
			SkillsUsed:       req.Skills,
			FallbackUsed:     false,
			EngineName:       eng.Name(),
		}
		if inserted, persistErr := s.logger.CommitUsage(ctx, entry, planLevel, tokensIn+tokensOut, history); persistErr != nil {
			log.Printf("[%s] commit usage failed: %v", traceID, persistErr)
			sseChan <- formatSSE("error", "failed to persist billing and audit logs")
			return
		} else if !inserted {
			log.Printf("[%s] duplicate request_id detected, skipped re-billing request_id=%s", traceID, requestID)
		}
		if err := s.persistProjectArtifacts(ctx, req, tenantID, userID, requestID, artifactCandidates); err != nil {
			log.Printf("[%s] failed to persist project artifacts: %v", traceID, err)
		}

		// Send done event
		doneData := map[string]any{
			"model":      finalModel,
			"tokens_in":  tokensIn,
			"tokens_out": tokensOut,
			"cost":       cost.StringFixed(6),
			"engine":     eng.Name(),
			"trace_id":   traceID,
			"request_id": requestID,
		}
		doneJSON, _ := json.Marshal(doneData)
		sseChan <- formatSSE("done", string(doneJSON))

		resultChan <- &StreamResult{
			Model:        finalModel,
			TokensIn:     tokensIn,
			TokensOut:    tokensOut,
			FallbackUsed: false,
			Response:     response.String(),
		}
	}()

	return sseChan, resultChan, nil
}

const DefaultSystemPrompt = `You are OpenClaw 2.0 (AI Operating Console / AIOC), a practical assistant for task execution and automation.
Use available tools responsibly and focus on accurate, concise, outcome-oriented responses.`

func ensureIdentity(msgs []llm.Message, skills []string, executionContext string) []llm.Message {
	skillDirective := buildSkillDirective(skills)
	systemPrompt := DefaultSystemPrompt
	if skillDirective != "" {
		systemPrompt = systemPrompt + "\n\n" + skillDirective
	}
	if executionContext != "" {
		systemPrompt = systemPrompt + "\n\n" + executionContext
	}

	if len(msgs) == 0 {
		return []llm.Message{{Role: "system", Content: systemPrompt}}
	}
	// If first message is already system, we prepend our identity
	if msgs[0].Role == "system" {
		if !strings.Contains(msgs[0].Content, "OpenClaw") {
			msgs[0].Content = systemPrompt + "\n\n" + msgs[0].Content
		}
		return msgs
	}
	// No system message, insert one
	newMsgs := make([]llm.Message, 0, len(msgs)+1)
	newMsgs = append(newMsgs, llm.Message{Role: "system", Content: systemPrompt})
	newMsgs = append(newMsgs, msgs...)
	return newMsgs
}

func (s *ChatService) buildExecutionContext(ctx context.Context, req *ChatRequest, userID string) string {
	lines := make([]string, 0, 4)
	if req.RoleID != "" {
		lines = append(lines, "Role: "+req.RoleID)
	}
	if req.TaskID != "" {
		lines = append(lines, "Task: "+req.TaskID)
	}
	if req.ProjectID != "" {
		lines = append(lines, "Project: "+req.ProjectID)
		if s.db != nil {
			var sourceCount int
			err := s.db.QueryRow(ctx,
				`SELECT COUNT(1)
				   FROM project_sources
				  WHERE project_id = $1 AND user_id = $2`,
				req.ProjectID, userID,
			).Scan(&sourceCount)
			if err == nil {
				lines = append(lines, fmt.Sprintf("Project sources available: %d", sourceCount))
				srcs := s.loadProjectSources(ctx, req.ProjectID, userID)
				if len(srcs) > 0 {
					max := len(srcs)
					if max > 3 {
						max = 3
					}
					previews := make([]string, 0, max)
					for i := 0; i < max; i++ {
						previews = append(previews, fmt.Sprintf("%s(%s)", srcs[i].Name, srcs[i].SourceType))
					}
					lines = append(lines, "Project source preview: "+strings.Join(previews, ", "))
				}
			}
		}
	}
	if len(lines) == 0 {
		return ""
	}
	return "Execution context:\n- " + strings.Join(lines, "\n- ")
}

func (s *ChatService) loadProjectSources(ctx context.Context, projectID, userID string) []engine.ProjectSource {
	if s.db == nil || projectID == "" || userID == "" {
		return nil
	}
	rows, err := s.db.Query(ctx,
		`SELECT source_id::text, source_type, name, content_text, file_path, link_url
		   FROM project_sources
		  WHERE project_id = $1 AND user_id = $2
		  ORDER BY created_at DESC
		  LIMIT 100`,
		projectID, userID,
	)
	if err != nil {
		return nil
	}
	defer rows.Close()

	out := make([]engine.ProjectSource, 0, 16)
	for rows.Next() {
		var src engine.ProjectSource
		if err := rows.Scan(
			&src.SourceID,
			&src.SourceType,
			&src.Name,
			&src.ContentText,
			&src.FilePath,
			&src.LinkURL,
		); err != nil {
			continue
		}
		if len(src.ContentText) > 2000 {
			src.ContentText = src.ContentText[:2000]
		}
		out = append(out, src)
	}
	return out
}

type artifactCandidate struct {
	OutputType string
	Filename   string
	FilePath   string
	SizeBytes  int64
	SHA256     string
}

func parseArtifactCandidate(toolName, result string) (artifactCandidate, bool) {
	if strings.TrimSpace(result) == "" {
		return artifactCandidate{}, false
	}
	var data map[string]any
	if err := json.Unmarshal([]byte(result), &data); err != nil {
		return artifactCandidate{}, false
	}
	c := artifactCandidate{}
	if fp, ok := data["file_path"].(string); ok && fp != "" {
		c.FilePath = fp
	}
	if bp, ok := data["bundle_path"].(string); ok && bp != "" {
		c.FilePath = bp
	}
	if ap, ok := data["audio_path"].(string); ok && ap != "" {
		c.FilePath = ap
	}
	if au, ok := data["audio_url"].(string); ok && au != "" && c.FilePath == "" {
		c.FilePath = au
	}
	if c.FilePath == "" {
		return artifactCandidate{}, false
	}
	if fn, ok := data["filename"].(string); ok && fn != "" {
		c.Filename = fn
	} else {
		c.Filename = filepath.Base(c.FilePath)
	}
	if ot, ok := data["actual_type"].(string); ok && ot != "" {
		c.OutputType = ot
	} else if rt, ok := data["requested_type"].(string); ok && rt != "" {
		c.OutputType = rt
	} else if toolName == "artifact_bundle_zip" {
		c.OutputType = "zip"
	} else if toolName == "tts_synthesize" {
		if fmtVal, ok := data["format"].(string); ok && strings.TrimSpace(fmtVal) != "" {
			c.OutputType = strings.TrimSpace(fmtVal)
		} else {
			c.OutputType = "audio"
		}
	} else {
		c.OutputType = "json"
	}
	if sz, ok := data["size_bytes"].(float64); ok {
		c.SizeBytes = int64(sz)
	}
	if sh, ok := data["sha256"].(string); ok {
		c.SHA256 = sh
	}
	return c, true
}

func (s *ChatService) persistProjectArtifacts(
	ctx context.Context,
	req *ChatRequest,
	tenantID, userID, runID string,
	candidates []artifactCandidate,
) error {
	if s.db == nil || req.ProjectID == "" || len(candidates) == 0 {
		return nil
	}
	projectUUID, err := uuid.Parse(req.ProjectID)
	if err != nil {
		return nil
	}
	runUUID, err := uuid.Parse(runID)
	if err != nil {
		return nil
	}
	for _, c := range candidates {
		if strings.TrimSpace(c.FilePath) == "" {
			continue
		}
		_, err := s.db.Exec(ctx,
			`INSERT INTO project_artifacts (
				artifact_id, project_id, tenant_id, user_id, run_id, role_id, task_id,
				output_type, filename, storage_path, size_bytes, sha256, metadata
			) VALUES (
				gen_random_uuid(), $1, $2, $3, $4, $5, $6,
				$7, $8, $9, $10, $11, '{}'::jsonb
			)`,
			projectUUID, tenantID, userID, runUUID, req.RoleID, req.TaskID,
			c.OutputType, c.Filename, c.FilePath, c.SizeBytes, c.SHA256,
		)
		if err != nil {
			return err
		}
	}
	return nil
}

func allowedToolsForPlanAndSkills(planLevel string, skills []string) []string {
	skillTools := map[string][]string{
		"shell_ops":                    {"execute_command"},
		"file_analysis":                {"request_data_chart", "artifact_render", "artifact_bundle_zip", "source_lookup"},
		"data_viz":                     {"request_data_chart"},
		"automation_planner":           {"request_calendar", "request_data_chart"},
		"student_knowledge_summary":    {"artifact_render", "source_lookup"},
		"student_kb_qa":                {"source_lookup"},
		"student_mistake_book":         {"artifact_render", "source_lookup"},
		"student_problem_solver":       {"artifact_render", "source_lookup"},
		"teacher_lesson_prep":          {"artifact_render", "source_lookup"},
		"teacher_student_segmentation": {"artifact_render", "request_data_chart", "source_lookup"},
		"doctor_case_structuring":      {"artifact_render", "source_lookup"},
		"doctor_followup_plan":         {"artifact_render", "source_lookup"},
		"lawyer_contract_risk_scan":    {"artifact_render", "source_lookup"},
		"lawyer_clause_diff":           {"artifact_render", "source_lookup"},
		"accountant_ledger_summary":    {"artifact_render", "request_data_chart", "source_lookup"},
		"accountant_reconciliation":    {"artifact_render", "source_lookup"},
		"support_ticket_summary":       {"artifact_render", "source_lookup"},
		"support_faq_extract":          {"artifact_render", "source_lookup"},
		"ecommerce_listing_copy":       {"artifact_render", "source_lookup"},
		"ecommerce_ops_report":         {"artifact_render", "request_data_chart", "source_lookup"},
		"tender_collection_push":       {"request_calendar", "source_lookup"},
		"ocr_extract":                  {"ocr_extract"},
		"asr_transcribe":               {"asr_transcribe"},
		"tts_synthesize":               {"tts_synthesize"},
		"multimodal_ocr":               {"ocr_extract"},
		"multimodal_asr":               {"asr_transcribe"},
		"multimodal_tts":               {"tts_synthesize"},
	}

	_ = planLevel // role/skill capabilities are now open by default for all users.

	final := make(map[string]struct{})
	if len(skills) == 0 {
		for _, tools := range skillTools {
			for _, tool := range tools {
				final[tool] = struct{}{}
			}
		}
	} else {
		for _, skill := range skills {
			for _, tool := range skillTools[skill] {
				final[tool] = struct{}{}
			}
		}
	}
	// Multimodal capabilities are open by default in v1 consumer build.
	final["ocr_extract"] = struct{}{}
	final["asr_transcribe"] = struct{}{}
	final["tts_synthesize"] = struct{}{}

	out := make([]string, 0, len(final))
	for tool := range final {
		out = append(out, tool)
	}
	return out
}

func buildSkillDirective(skills []string) string {
	if len(skills) == 0 {
		return ""
	}
	skillPrompts := map[string]string{
		"shell_ops":              "Prioritize precise terminal-based diagnostics and operation steps.",
		"file_analysis":          "Prioritize structured analysis of attached files and summarize findings.",
		"data_viz":               "Prefer producing chart-ready structured data and visual summaries.",
		"automation_planner":     "Prioritize reusable, scheduled workflow plans with explicit steps.",
		"tender_collection_push": "Prioritize fixed-point collection and periodic push delivery with concise summaries.",
		"ocr_extract":            "When image text extraction is needed, call ocr_extract and cite extracted text.",
		"asr_transcribe":         "When audio transcription is needed, call asr_transcribe before summarizing.",
		"tts_synthesize":         "When audio output is needed, call tts_synthesize and return the generated artifact.",
	}

	var directives []string
	for _, s := range skills {
		if d, ok := skillPrompts[s]; ok {
			directives = append(directives, d)
			continue
		}
		switch {
		case strings.HasPrefix(s, "student_"):
			directives = append(directives, "Student role task active. Focus on learning outcomes and concise structured deliverables.")
		case strings.HasPrefix(s, "teacher_"):
			directives = append(directives, "Teacher role task active. Focus on teaching plans, student analysis, and classroom-ready outputs.")
		case strings.HasPrefix(s, "doctor_"):
			directives = append(directives, "Doctor role task active. Focus on structured case records, risk notes, and follow-up actions.")
		case strings.HasPrefix(s, "lawyer_"):
			directives = append(directives, "Lawyer role task active. Focus on clause risks, legal clarity, and revision-ready outputs.")
		case strings.HasPrefix(s, "accountant_"):
			directives = append(directives, "Accountant role task active. Focus on reconciliation, ledger consistency, and auditable reports.")
		case strings.HasPrefix(s, "support_"):
			directives = append(directives, "Support role task active. Focus on ticket closure quality, FAQ extraction, and reusable responses.")
		case strings.HasPrefix(s, "ecommerce_"):
			directives = append(directives, "E-commerce role task active. Focus on listing quality, operating metrics, and conversion-oriented output.")
		}
	}
	if len(directives) == 0 {
		return ""
	}
	return "Active skills:\n- " + strings.Join(directives, "\n- ")
}
