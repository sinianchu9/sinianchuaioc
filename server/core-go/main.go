package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"github.com/aioc/core/config"
	"github.com/aioc/core/engine"
	"github.com/aioc/core/llm"
	"github.com/aioc/core/service"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
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

	if cfg.Server.Mode == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Connect to PostgreSQL
	ctx := context.Background()
	pgConfig, err := pgxpool.ParseConfig(cfg.Database.DSN())
	if err != nil {
		log.Fatalf("Failed to parse DB DSN: %v", err)
	}
	pgConfig.MaxConns = int32(cfg.Database.MaxConns)
	pgConfig.MinConns = int32(cfg.Database.MinConns)

	pool, err := pgxpool.NewWithConfig(ctx, pgConfig)
	if err != nil {
		log.Fatalf("Failed to connect to PostgreSQL: %v", err)
	}
	defer pool.Close()
	log.Println("✅ Core service connected to PostgreSQL")

	// Initialize LLM providers
	providers := make(map[string]llm.Provider)

	// DeepSeek (Economy mode)
	if cfg.LLM.DeepSeek.APIKey != "" {
		providers["deepseek-chat"] = llm.NewOpenAICompatible(
			"deepseek", cfg.LLM.DeepSeek.APIKey,
			cfg.LLM.DeepSeek.BaseURL, cfg.LLM.DeepSeek.DefaultModel,
			cfg.LLM.DeepSeek.TimeoutSeconds,
		)
		log.Println("✅ DeepSeek provider initialized")
	}

	// OpenAI / GPT-4 (Precision mode)
	if cfg.LLM.OpenAI.APIKey != "" {
		providers["gpt-4"] = llm.NewOpenAICompatible(
			"openai", cfg.LLM.OpenAI.APIKey,
			cfg.LLM.OpenAI.BaseURL, "gpt-4",
			cfg.LLM.OpenAI.TimeoutSeconds,
		)
		providers["gpt-4o-mini"] = llm.NewOpenAICompatible(
			"openai", cfg.LLM.OpenAI.APIKey,
			cfg.LLM.OpenAI.BaseURL, "gpt-4o-mini",
			cfg.LLM.OpenAI.TimeoutSeconds,
		)
		log.Println("✅ OpenAI providers initialized (gpt-4, gpt-4o-mini)")
	}

	// Ollama (Privacy mode)
	if cfg.LLM.Ollama.BaseURL != "" {
		providers["ollama/llama3"] = llm.NewOllamaProvider(
			cfg.LLM.Ollama.BaseURL, cfg.LLM.Ollama.DefaultModel,
			cfg.LLM.Ollama.TimeoutSeconds,
		)
		log.Println("✅ Ollama provider initialized")
	}

	// Initialize router, logger, cost calculator
	router := llm.NewRouter(pool, providers)
	auditLogger := service.NewAuditLogger(pool)
	costCalc := service.NewCostCalculator()

	// Initialize Engine Registry (pluggable execution engines)
	engineRegistry := engine.NewRegistry()
	engineRegistry.Register(engine.NewMockEngine())

	// Register OpenClaw engine if configured
	engineURL := os.Getenv("ENGINE_URL")
	if engineURL == "" {
		engineURL = "http://engine-openclaw:8000"
	}
	engineRegistry.Register(engine.NewOpenClawEngine(engineURL))
	log.Printf("✅ Engine Registry initialized (active: %s)", engineRegistry.ActiveName())

	chatSvc := service.NewChatService(router, auditLogger, costCalc, pool, cfg.Routing.FallbackTimeoutSeconds, engineRegistry)

	// Setup HTTP server
	r := gin.Default()

	// Internal health check
	r.GET("/internal/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"code": 1,
			"msg":  "ok",
			"data": gin.H{"service": "aioc-core", "version": "1.0.0"},
		})
	})

	// Internal chat stream endpoint (called by gateway reverse proxy)
	r.POST("/internal/chat/stream", func(c *gin.Context) {
		traceID := c.GetHeader("X-Trace-ID")
		userID := c.GetHeader("X-User-ID")
		tenantID := c.GetHeader("X-Tenant-ID")
		planLevel := c.GetHeader("X-Plan-Level")

		// Read request body
		body, err := io.ReadAll(c.Request.Body)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"code":     0,
				"msg":      "failed to read request body",
				"trace_id": traceID,
			})
			return
		}

		var chatReq service.ChatRequest
		if err := json.Unmarshal(body, &chatReq); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"code":     0,
				"msg":      "invalid request: " + err.Error(),
				"trace_id": traceID,
			})
			return
		}

		if len(chatReq.Messages) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{
				"code":     0,
				"msg":      "messages array is required and cannot be empty",
				"trace_id": traceID,
			})
			return
		}

		// Start streaming — route via engine or direct LLM
		var sseChan <-chan string
		if engineRegistry.ActiveName() != "mock" {
			sseChan, _, err = chatSvc.StreamChatViaEngine(c.Request.Context(), &chatReq, traceID, userID, tenantID, planLevel)
		} else {
			sseChan, _, err = chatSvc.StreamChat(c.Request.Context(), &chatReq, traceID, userID, tenantID, planLevel)
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"code":     0,
				"msg":      err.Error(),
				"trace_id": traceID,
			})
			return
		}

		// Set SSE headers
		c.Header("Content-Type", "text/event-stream")
		c.Header("Cache-Control", "no-cache")
		c.Header("Connection", "keep-alive")
		c.Header("X-Trace-ID", traceID)
		c.Header("X-Accel-Buffering", "no")

		// Stream SSE events
		c.Stream(func(w io.Writer) bool {
			event, ok := <-sseChan
			if !ok {
				return false
			}
			fmt.Fprint(w, event)
			c.Writer.Flush()
			return true
		})
	})

	// Start server
	addr := fmt.Sprintf(":%d", cfg.Server.CorePort)
	log.Printf("🚀 AIOC Core service starting on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("Failed to start core service: %v", err)
	}
}
