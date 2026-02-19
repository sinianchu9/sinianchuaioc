package llm

import (
	"context"
	"fmt"
	"log"
	"sync"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Router handles model selection based on mode and routing rules
type Router struct {
	mu        sync.RWMutex
	providers map[string]Provider      // model_name -> provider
	rules     map[string][]RoutingRule // mode -> sorted rules
	fallbacks map[string]string        // mode -> fallback_model
	db        *pgxpool.Pool
}

// RoutingRule defines a routing rule from the database
type RoutingRule struct {
	RuleID      string
	Name        string
	TargetModel string
	Mode        string
	MaxTokens   int
	Priority    int
	IsFallback  bool
}

// NewRouter creates a new model router
func NewRouter(db *pgxpool.Pool, providers map[string]Provider) *Router {
	r := &Router{
		providers: providers,
		rules:     make(map[string][]RoutingRule),
		fallbacks: make(map[string]string),
		db:        db,
	}
	r.loadRules()
	return r
}

// loadRules loads routing rules from the database
func (r *Router) loadRules() {
	rows, err := r.db.Query(context.Background(),
		`SELECT rule_id, name, target_model, mode, max_tokens, priority, condition_expr
		 FROM routing_rules WHERE enabled = true ORDER BY priority DESC`)
	if err != nil {
		log.Printf("⚠️ Failed to load routing rules: %v", err)
		r.setDefaults()
		return
	}
	defer rows.Close()

	r.mu.Lock()
	defer r.mu.Unlock()

	for rows.Next() {
		var rule RoutingRule
		var condExpr string
		if err := rows.Scan(&rule.RuleID, &rule.Name, &rule.TargetModel, &rule.Mode, &rule.MaxTokens, &rule.Priority, &condExpr); err != nil {
			continue
		}

		// Parse fallback condition
		rule.IsFallback = containsFallback(condExpr)

		if rule.IsFallback {
			r.fallbacks[rule.Mode] = rule.TargetModel
		} else {
			r.rules[rule.Mode] = append(r.rules[rule.Mode], rule)
		}
	}

	log.Printf("✅ Loaded %d routing rules, %d fallback rules",
		countRules(r.rules), len(r.fallbacks))
}

func containsFallback(expr string) bool {
	return len(expr) > 0 && (expr == "fallback" || contains(expr, "fallback") || contains(expr, "AND fallback"))
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && searchString(s, sub)
}

func searchString(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}

func countRules(m map[string][]RoutingRule) int {
	n := 0
	for _, v := range m {
		n += len(v)
	}
	return n
}

func (r *Router) setDefaults() {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.rules["economy"] = []RoutingRule{{TargetModel: "deepseek-chat", Mode: "economy", MaxTokens: 4096}}
	r.rules["precision"] = []RoutingRule{{TargetModel: "deepseek-chat", Mode: "precision", MaxTokens: 8192}}
	r.rules["privacy"] = []RoutingRule{{TargetModel: "ollama/llama3", Mode: "privacy", MaxTokens: 4096}}
	r.fallbacks["economy"] = "gpt-4o-mini"
	r.fallbacks["precision"] = "deepseek-chat"
}

// Route selects the appropriate model and provider for a given mode
func (r *Router) Route(mode string) (provider Provider, modelName string, maxTokens int, err error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	rules, ok := r.rules[mode]
	if !ok || len(rules) == 0 {
		return nil, "", 0, fmt.Errorf("no routing rules for mode: %s", mode)
	}

	// Use highest priority rule
	rule := rules[0]
	provider, ok = r.providers[rule.TargetModel]
	if !ok {
		return nil, "", 0, fmt.Errorf("no provider registered for model: %s", rule.TargetModel)
	}

	return provider, rule.TargetModel, rule.MaxTokens, nil
}

// Fallback returns the fallback provider for a given mode
func (r *Router) Fallback(mode string) (provider Provider, modelName string, err error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	model, ok := r.fallbacks[mode]
	if !ok {
		return nil, "", fmt.Errorf("no fallback configured for mode: %s", mode)
	}

	provider, ok = r.providers[model]
	if !ok {
		return nil, "", fmt.Errorf("no provider registered for fallback model: %s", model)
	}

	return provider, model, nil
}

// GetProvider returns a provider by model name
func (r *Router) GetProvider(modelName string) (Provider, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	p, ok := r.providers[modelName]
	return p, ok
}
