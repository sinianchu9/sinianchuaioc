package models

import (
	"time"

	"github.com/google/uuid"
	"github.com/shopspring/decimal"
)

// Tenant represents a tenant organization
type Tenant struct {
	TenantID  uuid.UUID       `json:"tenant_id"`
	Name      string          `json:"name"`
	Type      string          `json:"type"`
	PlanLevel string          `json:"plan_level"`
	Balance   decimal.Decimal `json:"balance"`
	Status    string          `json:"status"`
	CreatedAt time.Time       `json:"created_at"`
	UpdatedAt time.Time       `json:"updated_at"`
}

// User represents a user in the system
type User struct {
	UserID       uuid.UUID `json:"user_id"`
	TenantID     uuid.UUID `json:"tenant_id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	DisplayName  string    `json:"display_name"`
	Roles        []string  `json:"roles"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// Session represents a chat session
type Session struct {
	SessionID  uuid.UUID `json:"session_id"`
	UserID     uuid.UUID `json:"user_id"`
	Title      string    `json:"title"`
	ModelMode  string    `json:"model_mode"`
	TokenCount int       `json:"token_count"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// BillingLog represents a billing entry
type BillingLog struct {
	ID        int64           `json:"id"`
	TenantID  uuid.UUID       `json:"tenant_id"`
	UserID    uuid.UUID       `json:"user_id"`
	Timestamp time.Time       `json:"ts"`
	Model     string          `json:"model"`
	TokensIn  int             `json:"tokens_in"`
	TokensOut int             `json:"tokens_out"`
	Cost      decimal.Decimal `json:"cost"`
	RequestID uuid.UUID       `json:"request_id"`
	ClientID  *uuid.UUID      `json:"client_id,omitempty"`
	SessionID *uuid.UUID      `json:"session_id,omitempty"`
}

// AuditLog represents an audit entry
type AuditLog struct {
	ID               int64           `json:"id"`
	TenantID         uuid.UUID       `json:"tenant_id"`
	UserID           uuid.UUID       `json:"user_id"`
	Timestamp        time.Time       `json:"ts"`
	PromptSnapshot   string          `json:"prompt_snapshot,omitempty"`
	ResponseSnapshot string          `json:"response_snapshot,omitempty"`
	ModelUsed        string          `json:"model_used"`
	TokensIn         int             `json:"tokens_in"`
	TokensOut        int             `json:"tokens_out"`
	Cost             decimal.Decimal `json:"cost"`
	ToolsCalled      []string        `json:"tools_called,omitempty"`
	ClientID         *uuid.UUID      `json:"client_id,omitempty"`
	TraceID          string          `json:"trace_id"`
	FallbackUsed     bool            `json:"fallback_used"`
	SessionID        *uuid.UUID      `json:"session_id,omitempty"`
}

// RoutingRule represents a model routing rule
type RoutingRule struct {
	RuleID        uuid.UUID `json:"rule_id"`
	Name          string    `json:"name"`
	ConditionExpr string    `json:"condition_expr"`
	TargetModel   string    `json:"target_model"`
	Mode          string    `json:"mode"`
	MaxTokens     int       `json:"max_tokens"`
	Priority      int       `json:"priority"`
	Enabled       bool      `json:"enabled"`
}

// Plan represents a subscription plan
type Plan struct {
	PlanID       string          `json:"plan_id"`
	Name         string          `json:"name"`
	PriceMonthly decimal.Decimal `json:"price_monthly"`
	TokenQuota   int64           `json:"token_quota"`
	Features     map[string]any  `json:"features"`
}

// ClientRegistry represents a registered client
type ClientRegistry struct {
	ClientID     uuid.UUID      `json:"client_id"`
	Name         string         `json:"name"`
	Platform     string         `json:"platform"`
	MinVersion   string         `json:"min_version"`
	FeatureFlags map[string]any `json:"feature_flags"`
	Status       string         `json:"status"`
}
