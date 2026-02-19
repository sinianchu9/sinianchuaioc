/**
 * OpenClaw Engine Runner - HTTP/SSE Server
 * 
 * Exposes the Engine SPI endpoints:
 *   POST /execute  — Accepts AgentRequest, returns SSE stream of EngineEvents
 *   GET  /health   — Health check
 * 
 * This service is stateless: all context is passed per-request.
 * It MUST NOT connect to any database or manage sessions directly.
 */

import express from "express";
import { executeAgentRequest, type AgentRequest, type EngineEvent } from "./bridge.js";

const app = express();
app.use(express.json({ limit: "10mb" }));

const PORT = parseInt(process.env.PORT || "8000", 10);

// ─── Health Check ────────────────────────────────────────────────
app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    engine: "openclaw",
    version: "1.0.0",
    timestamp: new Date().toISOString(),
  });
});

// ─── Execute: Streaming Agent Request ────────────────────────────
app.post("/execute", async (req, res) => {
  const agentReq = req.body as AgentRequest;

  const traceId = agentReq.trace_id || "unknown";
  console.error(`[${traceId}] Execute Request:`, JSON.stringify(agentReq, null, 2));

  // Validate required fields
  if (!agentReq.messages || agentReq.messages.length === 0) {
    console.error(`[${traceId}] Validation failed: No messages`);
    res.status(400).json({
      type: "error",
      code: "INVALID_REQUEST",
      message: "messages array is required and must not be empty",
    });
    return;
  }

  if (!agentReq.config?.base_url) {
    console.error(`[${traceId}] Validation failed: Missing base_url`);
    res.status(400).json({
      type: "error",
      code: "INVALID_REQUEST",
      message: "config.base_url is required (BYOK)",
    });
    return;
  }
  
  if (!agentReq.config?.api_key) {
    console.warn(`[${traceId}] Warning: Missing API key. This is okay for some local models (e.g. Ollama).`);
  }

  console.error(`[${traceId}] Sending SSE headers...`);
  // Set SSE headers
  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });
  console.error(`[${traceId}] SSE headers sent.`);

  // Immediate heartbeat to flush headers and establish stream
  res.write(": heartbeat\n\n");

  // Keep-alive heartbeat every 15s
  const heartbeatInterval = setInterval(() => {
    if (!res.writableEnded) {
      res.write(": heartbeat\n\n");
    }
  }, 15000);

  try {
    await executeAgentRequest(agentReq, (event) => {
      if (!res.writableEnded) {
        res.write(`data: ${JSON.stringify(event)}\n\n`);
      }
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (!res.writableEnded) {
        res.write(`data: ${JSON.stringify({
            type: "error",
            code: "ENGINE_ERROR",
            message,
        })}\n\n`);
    }
  } finally {
    clearInterval(heartbeatInterval);
    if (!res.writableEnded) {
      res.write("data: [DONE]\n\n");
      res.end();
    }
  }
});

// ─── Start Server ────────────────────────────────────────────────
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 OpenClaw Engine Runner listening on port ${PORT}`);
  console.log(`   Health: http://0.0.0.0:${PORT}/health`);
  console.log(`   Execute: POST http://0.0.0.0:${PORT}/execute`);
});
