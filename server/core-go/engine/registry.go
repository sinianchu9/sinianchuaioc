package engine

import (
	"fmt"
	"log"
	"os"
	"sync"
)

// Registry manages available engine providers and selects the active one.
// Selection is driven by the ENGINE_PROVIDER environment variable.
type Registry struct {
	mu      sync.RWMutex
	engines map[string]AIEngine
	active  string
}

// NewRegistry creates an engine registry and selects the active engine
// based on the ENGINE_PROVIDER environment variable (default: "mock").
func NewRegistry() *Registry {
	provider := os.Getenv("ENGINE_PROVIDER")
	if provider == "" {
		provider = "mock"
	}
	return &Registry{
		engines: make(map[string]AIEngine),
		active:  provider,
	}
}

// Register adds an engine to the registry.
func (r *Registry) Register(engine AIEngine) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.engines[engine.Name()] = engine
	log.Printf("✅ Engine registered: %s", engine.Name())
}

// Active returns the currently selected engine.
func (r *Registry) Active() (AIEngine, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	engine, ok := r.engines[r.active]
	if !ok {
		return nil, fmt.Errorf("engine provider '%s' not registered (available: %v)", r.active, r.list())
	}
	return engine, nil
}

// Get returns a specific engine by name.
func (r *Registry) Get(name string) (AIEngine, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	e, ok := r.engines[name]
	return e, ok
}

// ActiveName returns the name of the currently selected engine.
func (r *Registry) ActiveName() string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.active
}

func (r *Registry) list() []string {
	names := make([]string, 0, len(r.engines))
	for k := range r.engines {
		names = append(names, k)
	}
	return names
}
