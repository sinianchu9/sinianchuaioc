package engine

import (
	"context"
	"fmt"
	"time"
)

// MockEngine is a test/CI engine that echoes user messages with simulated streaming.
// It never calls any real LLM — safe for automated testing and development.
type MockEngine struct{}

func NewMockEngine() *MockEngine {
	return &MockEngine{}
}

func (m *MockEngine) Name() string {
	return "mock"
}

func (m *MockEngine) Health(ctx context.Context) error {
	return nil
}

func (m *MockEngine) Capabilities() EngineCapabilities {
	return EngineCapabilities{
		SupportsStreaming: true,
		SupportsToolCall:  false,
		SupportedModes:    []string{"economy", "precision", "privacy"},
	}
}

// StreamExecute simulates a streaming response by echoing the last user message.
func (m *MockEngine) StreamExecute(ctx context.Context, req *AgentRequest) (<-chan EngineEvent, error) {
	// Find last user message
	lastMsg := "Hello from Mock Engine!"
	for i := len(req.Messages) - 1; i >= 0; i-- {
		if req.Messages[i].Role == "user" {
			lastMsg = req.Messages[i].Content
			break
		}
	}

	response := fmt.Sprintf("[Mock Engine] Echo: %s", lastMsg)
	ch := make(chan EngineEvent, 16)

	go func() {
		defer close(ch)

		// Simulate token-by-token streaming with small delays
		words := splitWords(response)
		tokensOut := 0
		for i, word := range words {
			select {
			case <-ctx.Done():
				ch <- EngineEvent{Type: EventError, Code: ErrCodeTimeout, Message: "request cancelled"}
				return
			default:
			}

			suffix := " "
			if i == len(words)-1 {
				suffix = ""
			}
			ch <- EngineEvent{Type: EventContent, Delta: word + suffix}
			tokensOut++

			time.Sleep(50 * time.Millisecond) // Simulate LLM latency
		}

		// Usage event
		ch <- EngineEvent{
			Type:      EventUsage,
			TokensIn:  len(req.Messages) * 10, // rough estimate
			TokensOut: tokensOut,
		}

		// Done
		ch <- EngineEvent{Type: EventDone}
	}()

	return ch, nil
}

func splitWords(s string) []string {
	var words []string
	current := ""
	for _, c := range s {
		if c == ' ' {
			if current != "" {
				words = append(words, current)
				current = ""
			}
		} else {
			current += string(c)
		}
	}
	if current != "" {
		words = append(words, current)
	}
	return words
}
