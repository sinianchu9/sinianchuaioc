package engine

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

// OpenClawEngine is the Go client that calls the OpenClaw Runner container
// via the standard Engine SPI (HTTP/SSE). It is completely decoupled from
// OpenClaw internals — it only speaks the standard protocol.
type OpenClawEngine struct {
	baseURL    string
	httpClient *http.Client
}

// NewOpenClawEngine creates a client for the OpenClaw Runner.
// baseURL is typically "http://engine-openclaw:8000" in Docker.
func NewOpenClawEngine(baseURL string) *OpenClawEngine {
	return &OpenClawEngine{
		baseURL: strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{
			// No global timeout — streaming responses can be long.
			// Per-request timeout is handled via context.
			Timeout: 0,
		},
	}
}

func (e *OpenClawEngine) Name() string {
	return "openclaw"
}

func (e *OpenClawEngine) Health(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, "GET", e.baseURL+"/health", nil)
	if err != nil {
		return fmt.Errorf("create health request: %w", err)
	}

	ctx2, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req = req.WithContext(ctx2)

	resp, err := e.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("engine health check failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("engine unhealthy (status %d): %s", resp.StatusCode, string(body))
	}
	return nil
}

func (e *OpenClawEngine) Capabilities() EngineCapabilities {
	return EngineCapabilities{
		SupportsStreaming: true,
		SupportsToolCall:  false, // Phase 2
		SupportedModes:    []string{"economy", "precision", "privacy"},
	}
}

// StreamExecute sends an AgentRequest to the OpenClaw Runner and streams events back.
func (e *OpenClawEngine) StreamExecute(ctx context.Context, req *AgentRequest) (<-chan EngineEvent, error) {
	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("marshal agent request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", e.baseURL+"/execute", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create execute request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "text/event-stream")

	resp, err := e.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("send request to openclaw engine: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		defer resp.Body.Close()
		errBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("openclaw engine error (status %d): %s", resp.StatusCode, string(errBody))
	}

	ch := make(chan EngineEvent, 128)
	go e.parseSSEStream(resp.Body, ch)
	return ch, nil
}

// parseSSEStream reads SSE events from the engine and converts them to EngineEvents.
func (e *OpenClawEngine) parseSSEStream(body io.ReadCloser, ch chan<- EngineEvent) {
	defer close(ch)
	defer body.Close()

	scanner := bufio.NewScanner(body)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()

		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, ":") {
			continue
		}

		// Parse SSE data line
		if !strings.HasPrefix(line, "data: ") {
			continue
		}

		data := strings.TrimPrefix(line, "data: ")

		// Check for stream end marker
		if data == "[DONE]" {
			ch <- EngineEvent{Type: EventDone}
			return
		}

		// Parse the JSON event
		var event EngineEvent
		if err := json.Unmarshal([]byte(data), &event); err != nil {
			log.Printf("⚠️ Failed to parse engine event: %v (data: %s)", err, data)
			continue
		}

		ch <- event

		// If the engine sent a fatal error, stop reading
		if event.Type == EventError {
			return
		}
	}

	if err := scanner.Err(); err != nil {
		ch <- EngineEvent{
			Type:    EventError,
			Code:    ErrCodeEngineError,
			Message: fmt.Sprintf("stream read error: %v", err),
		}
	}
}
