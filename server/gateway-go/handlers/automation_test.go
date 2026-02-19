package handlers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestExecuteAutomationParsesSSE(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-User-ID") != "user-1" {
			t.Fatalf("missing X-User-ID header")
		}
		if r.Header.Get("X-Plan-Level") != "pro" {
			t.Fatalf("missing X-Plan-Level header")
		}
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = fmt.Fprint(w, "event: content\n")
		_, _ = fmt.Fprint(w, "data: hello \n")
		_, _ = fmt.Fprint(w, "event: content\n")
		_, _ = fmt.Fprint(w, "data: world\n")
		_, _ = fmt.Fprint(w, "event: done\n")
		_, _ = fmt.Fprint(w, "data: {\"tokens_in\":12,\"tokens_out\":34,\"cost\":\"0.001000\",\"request_id\":\"11111111-1111-1111-1111-111111111111\"}\n")
	}))
	defer srv.Close()

	h := &AutomationHandler{coreURL: srv.URL}
	response, done, err := h.executeAutomation(
		context.Background(),
		"trace-1",
		"user-1",
		"tenant-1",
		"pro",
		"say hello",
		[]string{"shell_ops"},
	)
	if err != nil {
		t.Fatalf("executeAutomation returned error: %v", err)
	}
	if strings.TrimSpace(response) != "hello world" {
		t.Fatalf("unexpected response: %q", response)
	}
	if got := asInt(done["tokens_in"]); got != 12 {
		t.Fatalf("unexpected tokens_in: %d", got)
	}
	if got := asInt(done["tokens_out"]); got != 34 {
		t.Fatalf("unexpected tokens_out: %d", got)
	}
}

func TestExecuteAutomationRequiresDoneEvent(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = fmt.Fprint(w, "event: content\n")
		_, _ = fmt.Fprint(w, "data: partial\n")
	}))
	defer srv.Close()

	h := &AutomationHandler{coreURL: srv.URL}
	_, _, err := h.executeAutomation(
		context.Background(),
		"trace-2",
		"user-2",
		"tenant-2",
		"free",
		"test",
		nil,
	)
	if err == nil {
		t.Fatalf("expected missing done event error")
	}
}

func TestTruncateForRun(t *testing.T) {
	got := truncateForRun("abcdef", 3)
	if got != "abc...[truncated]" {
		t.Fatalf("unexpected truncation result: %q", got)
	}
}

