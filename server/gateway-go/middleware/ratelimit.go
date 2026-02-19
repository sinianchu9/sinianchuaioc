package middleware

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shopspring/decimal"
)

// RateLimiter implements per-user rate limiting and cost circuit breaker
type RateLimiter struct {
	mu                sync.Mutex
	requestCounts     map[string]*windowCounter
	costAccumulator   map[string]*costWindow
	maxRequestsPerMin int
	costLimitPerMin   float64
	db                *pgxpool.Pool
}

type windowCounter struct {
	count     int
	windowEnd time.Time
}

type costWindow struct {
	cost      decimal.Decimal
	windowEnd time.Time
}

// NewRateLimiter creates a new rate limiter with circuit breaker
func NewRateLimiter(maxRPM int, costLimit float64, db *pgxpool.Pool) *RateLimiter {
	rl := &RateLimiter{
		requestCounts:     make(map[string]*windowCounter),
		costAccumulator:   make(map[string]*costWindow),
		maxRequestsPerMin: maxRPM,
		costLimitPerMin:   costLimit,
		db:                db,
	}

	// Periodic cleanup of expired windows
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		for range ticker.C {
			rl.cleanup()
		}
	}()

	return rl
}

// Middleware returns a gin middleware for rate limiting
func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.GetString("user_id")
		if userID == "" {
			c.Next()
			return
		}

		// Rate limit check
		if !rl.allowRequest(userID) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"code":     0,
				"msg":      "rate limit exceeded, please slow down",
				"data":     nil,
				"trace_id": c.GetString("trace_id"),
			})
			c.Abort()
			return
		}

		// Cost circuit breaker check
		if rl.isCostBreached(userID) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"code":     0,
				"msg":      fmt.Sprintf("cost circuit breaker triggered: exceeded $%.2f/min limit", rl.costLimitPerMin),
				"data":     nil,
				"trace_id": c.GetString("trace_id"),
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

func (rl *RateLimiter) allowRequest(userID string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	counter, exists := rl.requestCounts[userID]

	if !exists || now.After(counter.windowEnd) {
		rl.requestCounts[userID] = &windowCounter{
			count:     1,
			windowEnd: now.Add(time.Minute),
		}
		return true
	}

	if counter.count >= rl.maxRequestsPerMin {
		return false
	}

	counter.count++
	return true
}

func (rl *RateLimiter) isCostBreached(userID string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	cw, exists := rl.costAccumulator[userID]

	if !exists || now.After(cw.windowEnd) {
		return false
	}

	limit := decimal.NewFromFloat(rl.costLimitPerMin)
	return cw.cost.GreaterThanOrEqual(limit)
}

// RecordCost adds cost to a user's rolling window (called after request completes)
func (rl *RateLimiter) RecordCost(userID string, cost decimal.Decimal) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	cw, exists := rl.costAccumulator[userID]

	if !exists || now.After(cw.windowEnd) {
		rl.costAccumulator[userID] = &costWindow{
			cost:      cost,
			windowEnd: now.Add(time.Minute),
		}
		return
	}

	cw.cost = cw.cost.Add(cost)
}

func (rl *RateLimiter) cleanup() {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	for k, v := range rl.requestCounts {
		if now.After(v.windowEnd) {
			delete(rl.requestCounts, k)
		}
	}
	for k, v := range rl.costAccumulator {
		if now.After(v.windowEnd) {
			delete(rl.costAccumulator, k)
		}
	}
}

// BillingPreCheck verifies that the user's tenant has sufficient balance and active plan
func BillingPreCheck(db *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		tenantID := c.GetString("tenant_id")
		if tenantID == "" {
			c.Next()
			return
		}

		var balance decimal.Decimal
		var planLevel, status string

		err := db.QueryRow(context.Background(),
			"SELECT balance, plan_level, status FROM tenants WHERE tenant_id = $1",
			tenantID,
		).Scan(&balance, &planLevel, &status)

		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"code":     0,
				"msg":      "failed to check billing status",
				"data":     nil,
				"trace_id": c.GetString("trace_id"),
			})
			c.Abort()
			return
		}

		if status != "active" {
			c.JSON(http.StatusForbidden, gin.H{
				"code":     0,
				"msg":      "account suspended",
				"data":     nil,
				"trace_id": c.GetString("trace_id"),
			})
			c.Abort()
			return
		}

		// Enterprise accounts don't need balance checks
		if planLevel == "enterprise" {
			c.Set("plan_level", planLevel)
			c.Next()
			return
		}

		// Free accounts: check if within quota
		if planLevel == "free" && balance.LessThanOrEqual(decimal.Zero) {
			c.JSON(http.StatusPaymentRequired, gin.H{
				"code":     0,
				"msg":      "insufficient balance, please upgrade your plan",
				"data":     nil,
				"trace_id": c.GetString("trace_id"),
			})
			c.Abort()
			return
		}

		c.Set("plan_level", planLevel)
		c.Set("balance", balance.String())
		c.Next()
	}
}

// ClientCheck validates client_id and version from request headers
func ClientCheck(db *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		clientID := c.GetHeader("X-Client-ID")
		clientVersion := c.GetHeader("X-Client-Version")

		// Client check is optional for API testing
		if clientID == "" {
			c.Next()
			return
		}

		var status, minVersion string
		err := db.QueryRow(context.Background(),
			"SELECT status, min_version FROM client_registry WHERE client_id = $1",
			clientID,
		).Scan(&status, &minVersion)

		if err != nil {
			c.JSON(http.StatusForbidden, gin.H{
				"code":     0,
				"msg":      "unregistered client",
				"data":     nil,
				"trace_id": c.GetString("trace_id"),
			})
			c.Abort()
			return
		}

		if status == "blocked" {
			c.JSON(http.StatusForbidden, gin.H{
				"code":     0,
				"msg":      "client has been blocked",
				"data":     nil,
				"trace_id": c.GetString("trace_id"),
			})
			c.Abort()
			return
		}

		if clientVersion != "" && compareSemver(clientVersion, minVersion) < 0 {
			c.JSON(http.StatusUpgradeRequired, gin.H{
				"code":     0,
				"msg":      fmt.Sprintf("client version %s is below minimum %s, please update", clientVersion, minVersion),
				"data":     nil,
				"trace_id": c.GetString("trace_id"),
			})
			c.Abort()
			return
		}

		c.Set("client_id", clientID)
		c.Next()
	}
}

func compareSemver(a, b string) int {
	pa := parseSemver(a)
	pb := parseSemver(b)
	for i := 0; i < 3; i++ {
		if pa[i] < pb[i] {
			return -1
		}
		if pa[i] > pb[i] {
			return 1
		}
	}
	return 0
}

func parseSemver(v string) [3]int {
	var out [3]int
	core := strings.SplitN(strings.TrimSpace(v), "-", 2)[0]
	parts := strings.Split(core, ".")
	for i := 0; i < len(parts) && i < 3; i++ {
		n, err := strconv.Atoi(parts[i])
		if err != nil || n < 0 {
			return [3]int{}
		}
		out[i] = n
	}
	return out
}
