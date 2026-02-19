package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"

	"github.com/aioc/gateway/config"
	"github.com/aioc/gateway/db"
	"github.com/aioc/gateway/handlers"
	"github.com/aioc/gateway/middleware"
	"github.com/gin-gonic/gin"
	"github.com/shopspring/decimal"
)

func main() {
	// Load configuration
	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		configPath = "configs/config.yaml"
	}

	cfg, err := config.Load(configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Set gin mode
	if cfg.Server.Mode == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Connect to PostgreSQL
	pgPool, err := db.Connect(cfg.Database.DSN(), cfg.Database.MaxConns, cfg.Database.MinConns)
	if err != nil {
		log.Fatalf("Failed to connect to PostgreSQL: %v", err)
	}
	defer pgPool.Close()
	log.Println("✅ Connected to PostgreSQL")

	// Connect to Redis
	redisClient, err := db.ConnectRedis(cfg.Redis.Addr(), cfg.Redis.Password, cfg.Redis.DB)
	if err != nil {
		log.Printf("⚠️ Failed to connect to Redis (non-fatal): %v", err)
	} else {
		defer redisClient.Close()
		log.Println("✅ Connected to Redis")
	}

	// Initialize handlers
	coreURL := fmt.Sprintf("http://localhost:%d", cfg.Server.CorePort)
	if envURL := os.Getenv("CORE_SERVICE_URL"); envURL != "" {
		coreURL = envURL
	}

	authHandler := handlers.NewAuthHandler(pgPool.Pool, cfg.JWT.Secret, cfg.JWT.ExpireHours, cfg.JWT.RefreshExpireHours)
	billingHandler := handlers.NewBillingHandler(pgPool.Pool)
	clientHandler := handlers.NewClientHandler(pgPool.Pool)
	skillsHandler := handlers.NewSkillsHandler()
	useCaseHandler := handlers.NewUseCaseHandler()
	projectHandler := handlers.NewProjectHandler(pgPool.Pool)
	sourceHandler := handlers.NewSourceHandler(pgPool.Pool)
	configCenterHandler := handlers.NewConfigCenterHandler()
	toolControlHandler := handlers.NewToolControlCenterHandler(pgPool.Pool)
	automationHandler := handlers.NewAutomationHandler(pgPool.Pool, coreURL)
	sessionHandler := handlers.NewSessionHandler(pgPool.Pool)

	// Initialize rate limiter
	rateLimiter := middleware.NewRateLimiter(
		cfg.RateLimit.RequestsPerMinute,
		cfg.RateLimit.CostLimitPerMinute,
		pgPool.Pool,
	)

	// Setup router
	r := gin.Default()

	// Global middleware
	r.Use(middleware.CORS())
	r.Use(middleware.TraceID())

	// Health check (no auth)
	r.GET("/api/v1/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"code":     1,
			"msg":      "ok",
			"data":     gin.H{"service": "aioc-gateway", "version": "1.0.0", "status": "healthy"},
			"trace_id": c.GetString("trace_id"),
		})
	})

	// Auth routes (no JWT required)
	auth := r.Group("/api/v1/auth")
	{
		auth.POST("/login", authHandler.Login)
		auth.POST("/refresh", authHandler.Refresh)
	}

	// Protected routes
	protected := r.Group("/api/v1")
	protected.Use(middleware.JWTAuth(cfg.JWT.Secret))
	protected.Use(middleware.ClientCheck(pgPool.Pool))
	{
		// Billing
		billing := protected.Group("/billing")
		billing.Use(middleware.BillingPreCheck(pgPool.Pool))
		{
			billing.GET("/summary", billingHandler.Summary)
			billing.POST("/verify_receipt", billingHandler.VerifyReceipt)
		}

		// Client
		protected.GET("/client/capabilities", clientHandler.Capabilities)
		protected.GET("/client/skills", skillsHandler.List)
		protected.GET("/client/use-cases", useCaseHandler.List)

		// Projects + local sources
		sources := protected.Group("/sources")
		{
			sources.GET("", sourceHandler.List)
			sources.POST("", sourceHandler.Create)
			sources.PUT("/:id", sourceHandler.Update)
			sources.DELETE("/:id", sourceHandler.Delete)
		}

		// Projects + selected source set
		projects := protected.Group("/projects")
		{
			projects.GET("", projectHandler.List)
			projects.POST("", projectHandler.Create)
			projects.GET("/:id/sources", projectHandler.ListSources)
			projects.POST("/:id/sources", projectHandler.CreateSource)
			projects.DELETE("/:id/sources/:source_id", projectHandler.DeleteSource)
		}

		// Sessions
		sessions := protected.Group("/sessions")
		{
			sessions.GET("", sessionHandler.List)
			sessions.GET("/:id", sessionHandler.Get)
			sessions.POST("", sessionHandler.Create)
			sessions.DELETE("/:id", sessionHandler.Delete)
		}

		// Automations
		automations := protected.Group("/automations")
		{
			automations.GET("", automationHandler.List)
			automations.POST("", automationHandler.Create)
			automations.POST("/:id/run", automationHandler.RunNow)
			automations.GET("/:id/runs", automationHandler.ListRuns)
			automations.PATCH("/:id/status", automationHandler.UpdateStatus)
			automations.DELETE("/:id", automationHandler.Delete)
		}

		admin := protected.Group("/admin")
		{
			configCenter := admin.Group("/config-center")
			{
				configCenter.GET("/manifest", configCenterHandler.GetManifest)
				configCenter.GET("/status", configCenterHandler.GetStatus)
				configCenter.POST("/validate", configCenterHandler.Validate)
				configCenter.PATCH("/integrations/:id", configCenterHandler.UpdateIntegration)
			}

			admin.GET("/tools", toolControlHandler.GetTools)
			admin.GET("/tools/:id", toolControlHandler.GetToolDetail)
			admin.POST("/tools/:id/toggle", toolControlHandler.ToggleTool)
			admin.GET("/integrations", toolControlHandler.ListIntegrations)
			admin.GET("/integrations/:id", toolControlHandler.GetIntegrationDetail)
			admin.POST("/integrations/:id/secret", toolControlHandler.UpdateIntegrationSecret)
			admin.POST("/integrations/:id/check", toolControlHandler.CheckIntegration)
			admin.GET("/status/summary", toolControlHandler.GetStatusSummary)
		}

		// Chat stream - reverse proxy to core service
		chatGroup := protected.Group("/chat")
		chatGroup.Use(rateLimiter.Middleware())
		chatGroup.Use(middleware.BillingPreCheck(pgPool.Pool))
		{
			chatGroup.POST("/stream", reverseProxy(coreURL, rateLimiter))
		}
	}

	// Start server
	addr := fmt.Sprintf(":%d", cfg.Server.GatewayPort)
	log.Printf("🚀 AIOC Gateway starting on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("Failed to start gateway: %v", err)
	}
}

// reverseProxy creates a reverse proxy handler to the core service
func reverseProxy(targetURL string, limiter *middleware.RateLimiter) gin.HandlerFunc {
	target, err := url.Parse(targetURL)
	if err != nil {
		log.Fatalf("Failed to parse core service URL: %v", err)
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.FlushInterval = -1 // Immediate flush for streaming

	return func(c *gin.Context) {
		// Forward trace_id, user_id, tenant_id as headers
		c.Request.Header.Set("X-Trace-ID", c.GetString("trace_id"))
		c.Request.Header.Set("X-User-ID", c.GetString("user_id"))
		c.Request.Header.Set("X-Tenant-ID", c.GetString("tenant_id"))
		c.Request.Header.Set("X-Plan-Level", c.GetString("plan_level"))
		if clientID := c.GetString("client_id"); clientID != "" {
			c.Request.Header.Set("X-Client-ID", clientID)
		}

		// Rewrite the path for core service
		c.Request.URL.Path = "/internal/chat/stream"

		capture := &costCaptureWriter{ResponseWriter: c.Writer}
		proxy.ServeHTTP(capture, c.Request)
		recordCostFromDoneEvent(c.GetString("user_id"), capture.String(), limiter)
	}
}

type costCaptureWriter struct {
	gin.ResponseWriter
	buf strings.Builder
}

func (w *costCaptureWriter) Write(data []byte) (int, error) {
	if w.buf.Len() < 128*1024 {
		_, _ = w.buf.Write(data)
	}
	return w.ResponseWriter.Write(data)
}

func (w *costCaptureWriter) String() string {
	return w.buf.String()
}

func recordCostFromDoneEvent(userID, payload string, limiter *middleware.RateLimiter) {
	if limiter == nil || userID == "" || payload == "" {
		return
	}

	idx := strings.LastIndex(payload, "event: done")
	if idx < 0 {
		return
	}
	segment := payload[idx:]
	dataIdx := strings.Index(segment, "\ndata: ")
	if dataIdx < 0 {
		return
	}
	dataLine := segment[dataIdx+7:]
	end := strings.IndexByte(dataLine, '\n')
	if end >= 0 {
		dataLine = dataLine[:end]
	}

	var done map[string]any
	if err := json.Unmarshal([]byte(strings.TrimSpace(dataLine)), &done); err != nil {
		return
	}

	rawCost, ok := done["cost"]
	if !ok {
		return
	}

	var cost decimal.Decimal
	switch v := rawCost.(type) {
	case string:
		c, err := decimal.NewFromString(v)
		if err != nil {
			return
		}
		cost = c
	case float64:
		cost = decimal.NewFromFloat(v)
	default:
		return
	}

	if cost.GreaterThan(decimal.Zero) {
		limiter.RecordCost(userID, cost)
	}
}
