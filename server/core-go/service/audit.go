package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shopspring/decimal"
)

// AuditLogger writes billing and audit logs to PostgreSQL
type AuditLogger struct {
	db *pgxpool.Pool
}

// NewAuditLogger creates a new audit logger
func NewAuditLogger(db *pgxpool.Pool) *AuditLogger {
	return &AuditLogger{db: db}
}

// LogEntry holds all data needed for both billing and audit logs
type LogEntry struct {
	TenantID         string
	UserID           string
	Model            string
	TokensIn         int
	TokensOut        int
	Cost             decimal.Decimal
	RequestID        string
	ClientID         string
	SessionID        string
	TraceID          string
	PromptSnapshot   string
	ResponseSnapshot string
	ToolsCalled      []string
	SkillsUsed       []string
	FallbackUsed     bool
	EngineName       string // Which engine processed this request (e.g. "openclaw", "mock", "")
}

// WriteBillingLog writes a billing log entry
func (l *AuditLogger) WriteBillingLog(ctx context.Context, entry *LogEntry) error {
	var clientID *uuid.UUID
	if entry.ClientID != "" {
		cid, err := uuid.Parse(entry.ClientID)
		if err == nil {
			clientID = &cid
		}
	}

	var sessionID *uuid.UUID
	if entry.SessionID != "" {
		sid, err := uuid.Parse(entry.SessionID)
		if err == nil {
			sessionID = &sid
		}
	}

	skillsJSON, _ := json.Marshal(entry.SkillsUsed)

	_, err := l.db.Exec(ctx,
		`INSERT INTO billing_logs (tenant_id, user_id, ts, model, tokens_in, tokens_out, cost, request_id, client_id, session_id, skills_used)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
		entry.TenantID, entry.UserID, time.Now(),
		entry.Model, entry.TokensIn, entry.TokensOut,
		entry.Cost, entry.RequestID, clientID, sessionID, string(skillsJSON),
	)
	if err != nil {
		log.Printf("❌ Failed to write billing log: %v", err)
		return fmt.Errorf("write billing log: %w", err)
	}
	return nil
}

// WriteAuditLog writes an audit log entry
func (l *AuditLogger) WriteAuditLog(ctx context.Context, entry *LogEntry) error {
	var clientID *uuid.UUID
	if entry.ClientID != "" {
		cid, err := uuid.Parse(entry.ClientID)
		if err == nil {
			clientID = &cid
		}
	}

	var sessionID *uuid.UUID
	if entry.SessionID != "" {
		sid, err := uuid.Parse(entry.SessionID)
		if err == nil {
			sessionID = &sid
		}
	}

	toolsJSON, _ := json.Marshal(entry.ToolsCalled)

	skillsJSON, _ := json.Marshal(entry.SkillsUsed)
	_, err := l.db.Exec(ctx,
		`INSERT INTO audit_logs (tenant_id, user_id, ts, prompt_snapshot, response_snapshot, model_used,
		  tokens_in, tokens_out, cost, tools_called, client_id, trace_id, fallback_used, session_id, skills_used)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
		entry.TenantID, entry.UserID, time.Now(),
		truncate(entry.PromptSnapshot, 10000),
		truncate(entry.ResponseSnapshot, 10000),
		entry.Model, entry.TokensIn, entry.TokensOut,
		entry.Cost, string(toolsJSON), clientID,
		entry.TraceID, entry.FallbackUsed, sessionID, string(skillsJSON),
	)
	if err != nil {
		log.Printf("❌ Failed to write audit log: %v", err)
		return fmt.Errorf("write audit log: %w", err)
	}
	return nil
}

// DeductBalance deducts cost from tenant balance
func (l *AuditLogger) DeductBalance(ctx context.Context, tenantID string, cost decimal.Decimal) error {
	_, err := l.db.Exec(ctx,
		`UPDATE tenants SET balance = balance - $1, updated_at = NOW() WHERE tenant_id = $2`,
		cost, tenantID,
	)
	if err != nil {
		log.Printf("❌ Failed to deduct balance: %v", err)
		return fmt.Errorf("deduct balance: %w", err)
	}
	return nil
}

// UpdateSessionTokens updates the token count for a session
func (l *AuditLogger) UpdateSessionTokens(ctx context.Context, sessionID, userID string, tokens int) error {
	if sessionID == "" {
		return nil
	}
	_, err := l.db.Exec(ctx,
		`UPDATE sessions
		 SET token_count = token_count + $1, updated_at = NOW()
		 WHERE session_id = $2 AND user_id = $3`,
		tokens, sessionID, userID,
	)
	return err
}

// UpdateSessionMessages replaces the message history for a session
func (l *AuditLogger) UpdateSessionMessages(ctx context.Context, sessionID, userID string, messages any) error {
	if sessionID == "" {
		return nil
	}

	msgsJSON, err := json.Marshal(messages)
	if err != nil {
		return fmt.Errorf("marshal messages: %w", err)
	}

	_, err = l.db.Exec(ctx,
		`UPDATE sessions
		 SET messages = $1, updated_at = NOW()
		 WHERE session_id = $2 AND user_id = $3`,
		string(msgsJSON), sessionID, userID,
	)
	return err
}

// CommitUsage atomically writes billing/audit records, deducts balance, and updates session data.
// Returns inserted=false when request_id is duplicated (idempotent replay).
func (l *AuditLogger) CommitUsage(
	ctx context.Context,
	entry *LogEntry,
	planLevel string,
	sessionTokenDelta int,
	sessionMessages any,
) (inserted bool, err error) {
	tx, err := l.db.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin tx: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback(ctx)
		}
	}()

	var clientID *uuid.UUID
	if entry.ClientID != "" {
		if cid, parseErr := uuid.Parse(entry.ClientID); parseErr == nil {
			clientID = &cid
		}
	}

	var sessionID *uuid.UUID
	if entry.SessionID != "" {
		if sid, parseErr := uuid.Parse(entry.SessionID); parseErr == nil {
			sessionID = &sid
		}
	}

	skillsJSON, _ := json.Marshal(entry.SkillsUsed)

	// Idempotency gate: only the first request_id is recorded and billed.
	var billingID int64
	err = tx.QueryRow(ctx,
		`INSERT INTO billing_logs (tenant_id, user_id, ts, model, tokens_in, tokens_out, cost, request_id, client_id, session_id, skills_used)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		 ON CONFLICT (request_id) DO NOTHING
		 RETURNING id`,
		entry.TenantID, entry.UserID, time.Now(),
		entry.Model, entry.TokensIn, entry.TokensOut,
		entry.Cost, entry.RequestID, clientID, sessionID, string(skillsJSON),
	).Scan(&billingID)
	if err == pgx.ErrNoRows {
		if commitErr := tx.Commit(ctx); commitErr != nil {
			return false, fmt.Errorf("commit duplicate tx: %w", commitErr)
		}
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("insert billing log: %w", err)
	}

	toolsJSON, _ := json.Marshal(entry.ToolsCalled)
	if _, err = tx.Exec(ctx,
		`INSERT INTO audit_logs (tenant_id, user_id, ts, prompt_snapshot, response_snapshot, model_used,
		  tokens_in, tokens_out, cost, tools_called, client_id, trace_id, fallback_used, session_id, skills_used)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
		entry.TenantID, entry.UserID, time.Now(),
		truncate(entry.PromptSnapshot, 10000),
		truncate(entry.ResponseSnapshot, 10000),
		entry.Model, entry.TokensIn, entry.TokensOut,
		entry.Cost, string(toolsJSON), clientID,
		entry.TraceID, entry.FallbackUsed, sessionID, string(skillsJSON),
	); err != nil {
		return false, fmt.Errorf("insert audit log: %w", err)
	}

	if planLevel != "enterprise" {
		if _, err = tx.Exec(ctx,
			`UPDATE tenants SET balance = balance - $1, updated_at = NOW() WHERE tenant_id = $2`,
			entry.Cost, entry.TenantID,
		); err != nil {
			return false, fmt.Errorf("deduct balance: %w", err)
		}
	}

	if entry.SessionID != "" {
		if _, err = tx.Exec(ctx,
			`UPDATE sessions
			 SET token_count = token_count + $1, updated_at = NOW()
			 WHERE session_id = $2 AND user_id = $3`,
			sessionTokenDelta, entry.SessionID, entry.UserID,
		); err != nil {
			return false, fmt.Errorf("update session tokens: %w", err)
		}

		if sessionMessages != nil {
			msgsJSON, marshalErr := json.Marshal(sessionMessages)
			if marshalErr != nil {
				return false, fmt.Errorf("marshal messages: %w", marshalErr)
			}
			if _, err = tx.Exec(ctx,
				`UPDATE sessions
				 SET messages = $1, updated_at = NOW()
				 WHERE session_id = $2 AND user_id = $3`,
				string(msgsJSON), entry.SessionID, entry.UserID,
			); err != nil {
				return false, fmt.Errorf("update session messages: %w", err)
			}
		}
	}

	if err = tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("commit tx: %w", err)
	}
	return true, nil
}

// truncate limits a string to maxLen characters (for DB storage)
func truncate(s string, maxLen int) string {
	runes := []rune(s)
	if len(runes) <= maxLen {
		return s
	}
	return string(runes[:maxLen]) + "...[truncated]"
}

// CostCalculator computes cost based on model and tokens
type CostCalculator struct {
	// Cost per 1M tokens (input, output) for each model
	costs map[string][2]decimal.Decimal
}

// NewCostCalculator creates a cost calculator with known model pricing
func NewCostCalculator() *CostCalculator {
	cc := &CostCalculator{
		costs: make(map[string][2]decimal.Decimal),
	}

	// DeepSeek pricing (per 1M tokens) - very affordable
	cc.costs["deepseek-chat"] = [2]decimal.Decimal{
		decimal.NewFromFloat(0.14), // input: $0.14/1M
		decimal.NewFromFloat(0.28), // output: $0.28/1M
	}

	// GPT-4 pricing (per 1M tokens)
	cc.costs["gpt-4"] = [2]decimal.Decimal{
		decimal.NewFromFloat(30.0), // input: $30/1M
		decimal.NewFromFloat(60.0), // output: $60/1M
	}

	// GPT-4o-mini pricing
	cc.costs["gpt-4o-mini"] = [2]decimal.Decimal{
		decimal.NewFromFloat(0.15), // input: $0.15/1M
		decimal.NewFromFloat(0.60), // output: $0.60/1M
	}

	// Ollama: free (local)
	cc.costs["ollama/llama3"] = [2]decimal.Decimal{
		decimal.Zero,
		decimal.Zero,
	}

	return cc
}

// Calculate computes the cost for a request
func (cc *CostCalculator) Calculate(model string, tokensIn, tokensOut int) decimal.Decimal {
	pricing, ok := cc.costs[model]
	if !ok {
		// Default to DeepSeek pricing for unknown models
		pricing = cc.costs["deepseek-chat"]
	}

	million := decimal.NewFromInt(1000000)
	inCost := pricing[0].Mul(decimal.NewFromInt(int64(tokensIn))).Div(million)
	outCost := pricing[1].Mul(decimal.NewFromInt(int64(tokensOut))).Div(million)

	return inCost.Add(outCost)
}
