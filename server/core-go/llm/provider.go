package llm

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Provider defines an LLM provider interface
type Provider interface {
	Name() string
	StreamChat(ctx context.Context, req *ChatRequest) (<-chan StreamChunk, error)
	GetConfig() (apiKey, baseURL string)
}

// ChatRequest represents a unified chat request
type ChatRequest struct {
	Model     string    `json:"model"`
	Messages  []Message `json:"messages"`
	MaxTokens int       `json:"max_tokens,omitempty"`
	Stream    bool      `json:"stream"`
}

// Message represents a chat message
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// StreamChunk represents a single SSE chunk from an LLM
type StreamChunk struct {
	Content      string `json:"content"`
	FinishReason string `json:"finish_reason,omitempty"`
	Model        string `json:"model,omitempty"`
	TokensIn     int    `json:"tokens_in,omitempty"`
	TokensOut    int    `json:"tokens_out,omitempty"`
	Error        error  `json:"-"`
	Done         bool   `json:"done"`
}

// OpenAICompatibleProvider works with OpenAI-compatible APIs (OpenAI, DeepSeek)
type OpenAICompatibleProvider struct {
	name       string
	apiKey     string
	baseURL    string
	model      string
	timeout    time.Duration
	httpClient *http.Client
}

// NewOpenAICompatible creates a provider for OpenAI-compatible APIs
func NewOpenAICompatible(name, apiKey, baseURL, model string, timeoutSec int) *OpenAICompatibleProvider {
	timeout := time.Duration(timeoutSec) * time.Second
	return &OpenAICompatibleProvider{
		name:    name,
		apiKey:  apiKey,
		baseURL: strings.TrimRight(baseURL, "/"),
		model:   model,
		timeout: timeout,
		httpClient: &http.Client{
			Timeout: timeout,
		},
	}
}

func (p *OpenAICompatibleProvider) Name() string {
	return p.name
}

func (p *OpenAICompatibleProvider) GetConfig() (apiKey, baseURL string) {
	return p.apiKey, p.baseURL
}

// StreamChat sends a streaming chat request and returns a channel of chunks
func (p *OpenAICompatibleProvider) StreamChat(ctx context.Context, req *ChatRequest) (<-chan StreamChunk, error) {
	// Build OpenAI-compatible request body
	body := map[string]any{
		"model":    req.Model,
		"messages": req.Messages,
		"stream":   true,
	}
	if req.MaxTokens > 0 {
		body["max_tokens"] = req.MaxTokens
	}

	jsonBody, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	url := p.baseURL + "/v1/chat/completions"
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+p.apiKey)
	httpReq.Header.Set("Accept", "text/event-stream")

	resp, err := p.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("send request to %s: %w", p.name, err)
	}

	if resp.StatusCode != http.StatusOK {
		defer resp.Body.Close()
		errBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("%s API error (status %d): %s", p.name, resp.StatusCode, string(errBody))
	}

	ch := make(chan StreamChunk, 64)
	go p.parseSSEStream(resp.Body, ch)
	return ch, nil
}

func (p *OpenAICompatibleProvider) parseSSEStream(body io.ReadCloser, ch chan<- StreamChunk) {
	defer close(ch)
	defer body.Close()

	scanner := bufio.NewScanner(body)
	// Increase buffer size for long responses
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	totalOut := 0

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

		// Check for stream end
		if data == "[DONE]" {
			ch <- StreamChunk{
				Done:      true,
				TokensOut: totalOut,
				Model:     p.model,
			}
			return
		}

		// Parse the JSON chunk
		var chunk openAIStreamChunk
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue // Skip malformed chunks
		}

		if len(chunk.Choices) > 0 {
			choice := chunk.Choices[0]
			content := choice.Delta.Content
			if content != "" {
				totalOut++
			}

			sc := StreamChunk{
				Content:      content,
				FinishReason: choice.FinishReason,
				Model:        chunk.Model,
			}

			// Extract usage if available
			if chunk.Usage != nil {
				sc.TokensIn = chunk.Usage.PromptTokens
				sc.TokensOut = chunk.Usage.CompletionTokens
			}

			if choice.FinishReason == "stop" {
				sc.Done = true
				if chunk.Usage != nil {
					sc.TokensOut = chunk.Usage.CompletionTokens
					sc.TokensIn = chunk.Usage.PromptTokens
				} else {
					sc.TokensOut = totalOut
				}
			}

			ch <- sc
		}
	}

	if err := scanner.Err(); err != nil {
		ch <- StreamChunk{Error: fmt.Errorf("stream read error: %w", err), Done: true}
	}
}

// OpenAI streaming response structures
type openAIStreamChunk struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Created int64  `json:"created"`
	Model   string `json:"model"`
	Choices []struct {
		Index int `json:"index"`
		Delta struct {
			Role    string `json:"role,omitempty"`
			Content string `json:"content,omitempty"`
		} `json:"delta"`
		FinishReason string `json:"finish_reason,omitempty"`
	} `json:"choices"`
	Usage *struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
		TotalTokens      int `json:"total_tokens"`
	} `json:"usage,omitempty"`
}

// OllamaProvider works with Ollama API
type OllamaProvider struct {
	name       string
	baseURL    string
	model      string
	timeout    time.Duration
	httpClient *http.Client
}

// NewOllamaProvider creates a new Ollama provider
func NewOllamaProvider(baseURL, model string, timeoutSec int) *OllamaProvider {
	timeout := time.Duration(timeoutSec) * time.Second
	return &OllamaProvider{
		name:    "ollama",
		baseURL: strings.TrimRight(baseURL, "/"),
		model:   model,
		timeout: timeout,
		httpClient: &http.Client{
			Timeout: timeout,
		},
	}
}

func (p *OllamaProvider) Name() string {
	return p.name
}

func (p *OllamaProvider) GetConfig() (apiKey, baseURL string) {
	return "", p.baseURL
}

// StreamChat sends a streaming chat request to Ollama
func (p *OllamaProvider) StreamChat(ctx context.Context, req *ChatRequest) (<-chan StreamChunk, error) {
	body := map[string]any{
		"model":    req.Model,
		"messages": req.Messages,
		"stream":   true,
	}

	jsonBody, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	url := p.baseURL + "/api/chat"
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := p.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("send request to ollama: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		defer resp.Body.Close()
		errBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ollama API error (status %d): %s", resp.StatusCode, string(errBody))
	}

	ch := make(chan StreamChunk, 64)
	go p.parseOllamaStream(resp.Body, ch)
	return ch, nil
}

func (p *OllamaProvider) parseOllamaStream(body io.ReadCloser, ch chan<- StreamChunk) {
	defer close(ch)
	defer body.Close()

	decoder := json.NewDecoder(body)
	totalOut := 0

	for {
		var chunk ollamaStreamChunk
		if err := decoder.Decode(&chunk); err != nil {
			if err != io.EOF {
				ch <- StreamChunk{Error: fmt.Errorf("ollama stream error: %w", err), Done: true}
			}
			return
		}

		content := chunk.Message.Content
		if content != "" {
			totalOut++
		}

		sc := StreamChunk{
			Content: content,
			Model:   chunk.Model,
			Done:    chunk.Done,
		}

		if chunk.Done {
			sc.TokensIn = chunk.PromptEvalCount
			sc.TokensOut = chunk.EvalCount
			if sc.TokensOut == 0 {
				sc.TokensOut = totalOut
			}
		}

		ch <- sc

		if chunk.Done {
			return
		}
	}
}

type ollamaStreamChunk struct {
	Model   string `json:"model"`
	Message struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	} `json:"message"`
	Done            bool `json:"done"`
	PromptEvalCount int  `json:"prompt_eval_count,omitempty"`
	EvalCount       int  `json:"eval_count,omitempty"`
}
