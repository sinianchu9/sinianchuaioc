package engine

import (
	"context"
	"encoding/json"
)

// AIEngine defines the standard execution protocol (Engine SPI).
// Any engine (OpenClaw, Mock, AutoGPT, etc.) must implement this interface.
// The Go orchestrator depends ONLY on this interface — never on engine internals.
type AIEngine interface {
	// StreamExecute sends an AgentRequest to the engine and returns a channel of events.
	// The channel is closed when the engine finishes or encounters a fatal error.
	StreamExecute(ctx context.Context, req *AgentRequest) (<-chan EngineEvent, error)

	// Health checks if the engine service is reachable and ready.
	Health(ctx context.Context) error

	// Capabilities returns the engine's supported features.
	Capabilities() EngineCapabilities

	// Name returns the engine's identifier (e.g. "openclaw", "mock").
	Name() string
}

// AgentRequest is the standard input sent from Go Core to any engine.
// All context (messages, config, tools) is provided per-request — engines are stateless.
type AgentRequest struct {
	SessionID      string          `json:"session_id"`
	Messages       []Message       `json:"messages"`
	Config         ModelConfig     `json:"config"`
	Skills         []string        `json:"skills,omitempty"`
	RoleID         string          `json:"role_id,omitempty"`
	TaskID         string          `json:"task_id,omitempty"`
	ProjectID      string          `json:"project_id,omitempty"`
	ProjectSources []ProjectSource `json:"project_sources,omitempty"`
	AllowedTools   []string        `json:"allowed_tools,omitempty"`
	PlanLevel      string          `json:"plan_level,omitempty"`
	Mode           string          `json:"mode"` // economy, precision, privacy
	TraceID        string          `json:"trace_id"`
	TenantID       string          `json:"tenant_id"`
	UserID         string          `json:"user_id"`
	ClientID       string          `json:"client_id,omitempty"`
}

type ProjectSource struct {
	SourceID    string `json:"source_id"`
	SourceType  string `json:"source_type"`
	Name        string `json:"name"`
	ContentText string `json:"content_text,omitempty"`
	FilePath    string `json:"file_path,omitempty"`
	LinkURL     string `json:"link_url,omitempty"`
}

// Message represents a single chat message in the conversation history.
type Message struct {
	Role    string `json:"role"` // system, user, assistant, tool
	Content string `json:"content"`
}

// ModelConfig carries the LLM configuration for this request.
// api_key and base_url are passed per-request to support BYOK and key pools.
type ModelConfig struct {
	ModelName   string  `json:"model_name"`
	BaseURL     string  `json:"base_url"`
	APIKey      string  `json:"api_key"`
	MaxTokens   int     `json:"max_tokens,omitempty"`
	Temperature float64 `json:"temperature,omitempty"`
}

// EngineEvent is a single event in the engine's output stream.
// Events are JSON-serialized and sent as SSE from the engine to Go Core.
type EngineEvent struct {
	Type string `json:"type"` // content, tool_call, tool_result, ui_component, usage, error, done
	// For type=content
	Delta string `json:"delta,omitempty"`
	// For type=tool_call (Phase 2)
	Tool string          `json:"tool,omitempty"`
	Args json.RawMessage `json:"args,omitempty"`
	// For type=tool_result
	Result string `json:"result,omitempty"`
	// For type=ui_component
	Component     string          `json:"component,omitempty"`
	ComponentArgs json.RawMessage `json:"component_args,omitempty"`
	// For type=usage
	TokensIn  int `json:"tokens_in,omitempty"`
	TokensOut int `json:"tokens_out,omitempty"`
	// For type=error
	Code    string `json:"code,omitempty"`
	Message string `json:"message,omitempty"`
}

// EngineCapabilities describes what an engine supports.
type EngineCapabilities struct {
	SupportsStreaming bool     `json:"supports_streaming"`
	SupportsToolCall  bool     `json:"supports_tool_call"`
	SupportedModes    []string `json:"supported_modes"` // e.g. ["economy","precision","privacy"]
}

// Standard event type constants
const (
	EventContent     = "content"
	EventToolCall    = "tool_call"
	EventToolResult  = "tool_result"
	EventUIComponent = "ui_component"
	EventUsage       = "usage"
	EventError       = "error"
	EventDone        = "done"
)

// Standard error codes
const (
	ErrCodeEngineError   = "ENGINE_ERROR"
	ErrCodeTimeout       = "ENGINE_TIMEOUT"
	ErrCodeModelNotFound = "MODEL_NOT_FOUND"
	ErrCodeAuthFailed    = "AUTH_FAILED"
	ErrCodeRateLimited   = "RATE_LIMITED"
)
