package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shopspring/decimal"
)

// scheduledAutomation holds the data needed to fire one automation run.
type scheduledAutomation struct {
	automationID string
	userID       string
	tenantID     string
	planLevel    string
	prompt       string
	skills       []string
}

// AutomationScheduler is a background worker that periodically fires
// automations whose interval is due.  It runs inside the gateway process and
// reuses AutomationHandler.executeAutomation so the execution path is
// identical to a manual run-now trigger.
type AutomationScheduler struct {
	db      *pgxpool.Pool
	coreURL string

	tickInterval time.Duration // how often we poll the DB (default 60s)

	mu     sync.Mutex
	wg     sync.WaitGroup
	cancel context.CancelFunc
}

// NewAutomationScheduler creates a scheduler with a 60-second poll interval.
func NewAutomationScheduler(db *pgxpool.Pool, coreURL string) *AutomationScheduler {
	return &AutomationScheduler{
		db:           db,
		coreURL:      coreURL,
		tickInterval: 60 * time.Second,
	}
}

// Start begins the scheduler loop.  It blocks until ctx is cancelled or Stop
// is called; run it in a goroutine.
func (s *AutomationScheduler) Start(ctx context.Context) {
	ctx, cancel := context.WithCancel(ctx)
	s.mu.Lock()
	s.cancel = cancel
	s.mu.Unlock()

	log.Println("⏰ AutomationScheduler started (poll interval:", s.tickInterval, ")")

	// Fire an initial tick immediately so automations that are due at startup
	// do not have to wait a full interval.
	s.tick(ctx)

	ticker := time.NewTicker(s.tickInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Println("⏰ AutomationScheduler stopping, waiting for running jobs…")
			s.wg.Wait()
			log.Println("⏰ AutomationScheduler stopped")
			return
		case <-ticker.C:
			s.tick(ctx)
		}
	}
}

// Stop signals the scheduler to stop and waits for in-flight runs to finish.
func (s *AutomationScheduler) Stop() {
	s.mu.Lock()
	cancel := s.cancel
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	s.wg.Wait()
}

// tick queries the DB for all due automations and dispatches each one.
func (s *AutomationScheduler) tick(ctx context.Context) {
	due, err := s.queryDue(ctx)
	if err != nil {
		log.Printf("⏰ scheduler: error querying due automations: %v", err)
		return
	}
	if len(due) == 0 {
		return
	}
	log.Printf("⏰ scheduler: dispatching %d due automation(s)", len(due))
	for _, a := range due {
		s.wg.Add(1)
		go func(a scheduledAutomation) {
			defer s.wg.Done()
			s.dispatch(ctx, a)
		}(a)
	}
}

// queryDue returns all active automations whose next-run time has arrived.
//
// Trigger conditions:
//   - last_run_at IS NULL  → never run before, fire immediately
//   - last_run_at + interval_hours <= NOW() → interval has elapsed
func (s *AutomationScheduler) queryDue(ctx context.Context) ([]scheduledAutomation, error) {
	rows, err := s.db.Query(ctx, `
		SELECT
			a.automation_id,
			a.user_id,
			a.tenant_id,
			COALESCE(u.plan_level, 'free') AS plan_level,
			a.prompt,
			a.skills
		FROM automations a
		JOIN users u ON u.user_id = a.user_id
		WHERE a.status = 'active'
		  AND (
		      a.last_run_at IS NULL
		   OR a.last_run_at + (a.interval_hours * INTERVAL '1 hour') <= NOW()
		  )
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []scheduledAutomation
	for rows.Next() {
		var a scheduledAutomation
		var aid, uid, tid uuid.UUID
		var skillsRaw []byte

		if err := rows.Scan(&aid, &uid, &tid, &a.planLevel, &a.prompt, &skillsRaw); err != nil {
			log.Printf("⏰ scheduler: scan error: %v", err)
			continue
		}
		a.automationID = aid.String()
		a.userID = uid.String()
		a.tenantID = tid.String()
		_ = json.Unmarshal(skillsRaw, &a.skills)
		result = append(result, a)
	}
	return result, rows.Err()
}

// dispatch executes a single automation and records the result.
func (s *AutomationScheduler) dispatch(ctx context.Context, a scheduledAutomation) {
	traceID := fmt.Sprintf("sched-%s-%d", a.automationID[:8], time.Now().UnixNano())
	log.Printf("⏰ scheduler: running automation %s (user=%s)", a.automationID, a.userID)

	// Claim the slot: update last_run_at immediately so a concurrent tick
	// does not double-fire the same automation.
	_, err := s.db.Exec(ctx,
		`UPDATE automations
		    SET last_run_at = NOW(), updated_at = NOW()
		  WHERE automation_id = $1 AND status = 'active'`,
		a.automationID,
	)
	if err != nil {
		log.Printf("⏰ scheduler: failed to claim automation %s: %v", a.automationID, err)
		return
	}

	// Insert a 'running' run record.
	runID := uuid.New()
	_, _ = s.db.Exec(ctx,
		`INSERT INTO automation_runs
		 (run_id, automation_id, tenant_id, user_id, status, started_at)
		 VALUES ($1,$2,$3,$4,'running',NOW())`,
		runID, a.automationID, a.tenantID, a.userID,
	)

	// Reuse the existing execution helper via an ephemeral AutomationHandler.
	handler := &AutomationHandler{db: s.db, coreURL: s.coreURL}
	response, doneData, execErr := handler.executeAutomation(
		ctx, traceID, a.userID, a.tenantID, a.planLevel, a.prompt, a.skills,
	)
	if execErr != nil {
		log.Printf("⏰ scheduler: automation %s failed: %v", a.automationID, execErr)
		_, _ = s.db.Exec(ctx,
			`UPDATE automation_runs
			    SET status='failed', finished_at=NOW(), error_message=$1
			  WHERE run_id=$2`,
			execErr.Error(), runID,
		)
		return
	}

	cost, _ := decimal.NewFromString(fmt.Sprintf("%v", doneData["cost"]))
	var requestID *uuid.UUID
	if rawReq, ok := doneData["request_id"].(string); ok {
		if parsed, parseErr := uuid.Parse(rawReq); parseErr == nil {
			requestID = &parsed
		}
	}
	tokensIn := asInt(doneData["tokens_in"])
	tokensOut := asInt(doneData["tokens_out"])

	_, _ = s.db.Exec(ctx,
		`UPDATE automation_runs
		    SET status='completed', finished_at=NOW(),
		        response_preview=$1, tokens_in=$2, tokens_out=$3,
		        cost=$4, request_id=$5
		  WHERE run_id=$6`,
		truncateForRun(response, 5000), tokensIn, tokensOut, cost, requestID, runID,
	)

	log.Printf("⏰ scheduler: automation %s completed (run=%s tokens_in=%d tokens_out=%d cost=%s)",
		a.automationID, runID, tokensIn, tokensOut, cost.StringFixed(6))
}

// IsDue returns true if an automation with the given intervalHours and
// lastRunAt is currently due to fire.  lastRunAt == nil means never run.
// Exported only for unit testing.
func IsDue(intervalHours int, lastRunAt *time.Time, now time.Time) bool {
	if lastRunAt == nil {
		return true
	}
	return now.Sub(*lastRunAt) >= time.Duration(intervalHours)*time.Hour
}
