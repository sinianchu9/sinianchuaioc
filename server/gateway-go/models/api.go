package models

// APIResponse is the unified response format for all API endpoints
type APIResponse struct {
	Code    int    `json:"code"`     // 1 = success, 0 = error
	Msg     string `json:"msg"`      // Human-readable message
	Data    any    `json:"data"`     // Response payload
	TraceID string `json:"trace_id"` // Request trace ID
}

// LoginRequest represents a login payload
type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
}

// LoginResponse holds JWT tokens after successful login
type LoginResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"` // seconds
	User         *User  `json:"user"`
}

// RefreshRequest represents a token refresh payload
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// ChatStreamRequest represents a chat stream request
type ChatStreamRequest struct {
	SessionID string        `json:"session_id"`
	Messages  []ChatMessage `json:"messages" binding:"required"`
	Mode      string        `json:"mode"` // economy, precision, privacy
	Skills    []string      `json:"skills,omitempty"`
	RoleID    string        `json:"role_id,omitempty"`
	TaskID    string        `json:"task_id,omitempty"`
	ProjectID string        `json:"project_id,omitempty"`
	ClientID  string        `json:"client_id"`
}

// ChatMessage represents a single message in a conversation
type ChatMessage struct {
	Role    string `json:"role" binding:"required"` // system, user, assistant
	Content string `json:"content" binding:"required"`
}

// BillingSummary holds usage statistics
type BillingSummary struct {
	TotalTokensIn  int64  `json:"total_tokens_in"`
	TotalTokensOut int64  `json:"total_tokens_out"`
	TotalCost      string `json:"total_cost"` // decimal string
	RequestCount   int64  `json:"request_count"`
	PlanLevel      string `json:"plan_level"`
	Balance        string `json:"balance"` // decimal string
	Period         string `json:"period"`  // e.g., "2024-01"
}

// ClientCapabilities represents feature toggles for a client
type ClientCapabilities struct {
	Chat        bool     `json:"chat"`
	Stream      bool     `json:"stream"`
	Tools       bool     `json:"tools"`
	RAG         bool     `json:"rag"`
	Models      []string `json:"models"`
	MaxSessions int      `json:"max_sessions"`
	PlanLevel   string   `json:"plan_level"`
}

// SkillDescriptor describes a user-facing capability skill.
type SkillDescriptor struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Category    string   `json:"category"`
	MinPlan     string   `json:"min_plan"`
	SourceURL   string   `json:"source_url,omitempty"`
	Provider    string   `json:"provider,omitempty"`
	Tools       []string `json:"tools"`
}

// SessionListItem represents a session in a list
type SessionListItem struct {
	SessionID  string        `json:"session_id"`
	Title      string        `json:"title"`
	ModelMode  string        `json:"model_mode"`
	TokenCount int           `json:"token_count"`
	Messages   []ChatMessage `json:"messages,omitempty"`
	CreatedAt  string        `json:"created_at"`
	UpdatedAt  string        `json:"updated_at"`
}

// VerifyReceiptRequest represents an IAP receipt verification
type VerifyReceiptRequest struct {
	Platform      string `json:"platform" binding:"required"` // ios, android
	Receipt       string `json:"receipt" binding:"required"`
	TransactionID string `json:"transaction_id"`
}

type CreateAutomationRequest struct {
	Name           string   `json:"name" binding:"required,min=2,max=200"`
	Prompt         string   `json:"prompt" binding:"required,min=2"`
	Skills         []string `json:"skills,omitempty"`
	ScheduleKind   string   `json:"schedule_kind"` // interval | daily
	IntervalHours  int      `json:"interval_hours"`
	Timezone       string   `json:"timezone"`
	RunImmediately bool     `json:"run_immediately"`
}

type AutomationItem struct {
	AutomationID   string   `json:"automation_id"`
	Name           string   `json:"name"`
	Prompt         string   `json:"prompt"`
	Skills         []string `json:"skills"`
	ScheduleKind   string   `json:"schedule_kind"`
	IntervalHours  int      `json:"interval_hours"`
	Timezone       string   `json:"timezone"`
	Status         string   `json:"status"`
	RunImmediately bool     `json:"run_immediately"`
	CreatedAt      string   `json:"created_at"`
	UpdatedAt      string   `json:"updated_at"`
}

type AutomationRunItem struct {
	RunID           string `json:"run_id"`
	AutomationID    string `json:"automation_id"`
	Status          string `json:"status"`
	StartedAt       string `json:"started_at"`
	FinishedAt      string `json:"finished_at,omitempty"`
	ResponsePreview string `json:"response_preview,omitempty"`
	TokensIn        int    `json:"tokens_in"`
	TokensOut       int    `json:"tokens_out"`
	Cost            string `json:"cost"`
	RequestID       string `json:"request_id,omitempty"`
	ErrorMessage    string `json:"error_message,omitempty"`
}

type UseCaseTask struct {
	TaskID        string   `json:"task_id"`
	Title         string   `json:"title"`
	Description   string   `json:"description"`
	DefaultSkills []string `json:"default_skills"`
	Mode          string   `json:"mode"`
	Category      string   `json:"category"`
	MinPlan       string   `json:"min_plan"`
}

type UseCaseRole struct {
	RoleID      string        `json:"role_id"`
	Title       string        `json:"title"`
	Description string        `json:"description"`
	Tasks       []UseCaseTask `json:"tasks"`
}

type UseCaseGenericSkill struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

type ProjectItem struct {
	ProjectID   string `json:"project_id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Status      string `json:"status"`
	CreatedAt   string `json:"created_at"`
	UpdatedAt   string `json:"updated_at"`
}

type ProjectSourceItem struct {
	SourceID     string `json:"source_id"`
	ProjectID    string `json:"project_id"`
	SourceType   string `json:"source_type"`
	Name         string `json:"name"`
	ContentText  string `json:"content_text,omitempty"`
	FilePath     string `json:"file_path,omitempty"`
	LinkURL      string `json:"link_url,omitempty"`
	MetadataJSON string `json:"metadata_json,omitempty"`
	CreatedAt    string `json:"created_at"`
}

type UserSourceItem struct {
	SourceID     string `json:"source_id"`
	SourceType   string `json:"source_type"`
	Name         string `json:"name"`
	ContentText  string `json:"content_text,omitempty"`
	FilePath     string `json:"file_path,omitempty"`
	LinkURL      string `json:"link_url,omitempty"`
	MetadataJSON string `json:"metadata_json,omitempty"`
	CreatedAt    string `json:"created_at"`
	UpdatedAt    string `json:"updated_at"`
}
