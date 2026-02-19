package config

import (
	"fmt"
	"os"
	"strconv"

	"gopkg.in/yaml.v3"
)

// Config holds configuration for the core service
type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Database DatabaseConfig `yaml:"database"`
	Redis    RedisConfig    `yaml:"redis"`
	LLM      LLMConfig     `yaml:"llm"`
	Routing  RoutingConfig  `yaml:"routing"`
}

type ServerConfig struct {
	CorePort int    `yaml:"core_port"`
	Mode     string `yaml:"mode"`
}

type DatabaseConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	User     string `yaml:"user"`
	Password string `yaml:"password"`
	DBName   string `yaml:"dbname"`
	MaxConns int    `yaml:"max_conns"`
	MinConns int    `yaml:"min_conns"`
}

func (d *DatabaseConfig) DSN() string {
	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=disable",
		d.User, d.Password, d.Host, d.Port, d.DBName)
}

type RedisConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Password string `yaml:"password"`
	DB       int    `yaml:"db"`
}

func (r *RedisConfig) Addr() string {
	return fmt.Sprintf("%s:%d", r.Host, r.Port)
}

type LLMConfig struct {
	DeepSeek LLMProviderConfig `yaml:"deepseek"`
	OpenAI   LLMProviderConfig `yaml:"openai"`
	Ollama   LLMProviderConfig `yaml:"ollama"`
}

type LLMProviderConfig struct {
	APIKey         string `yaml:"api_key"`
	BaseURL        string `yaml:"base_url"`
	DefaultModel   string `yaml:"default_model"`
	TimeoutSeconds int    `yaml:"timeout_seconds"`
}

type RoutingConfig struct {
	DefaultMode            string `yaml:"default_mode"`
	FallbackTimeoutSeconds int    `yaml:"fallback_timeout_seconds"`
}

// Load reads config from YAML file with env overlay
func Load(path string) (*Config, error) {
	cfg := &Config{}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}

	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	cfg.overlayEnv()
	return cfg, nil
}

func (c *Config) overlayEnv() {
	if v := os.Getenv("CORE_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			c.Server.CorePort = p
		}
	}
	if v := os.Getenv("AIOC_MODE"); v != "" {
		c.Server.Mode = v
	}
	if v := os.Getenv("DB_HOST"); v != "" {
		c.Database.Host = v
	}
	if v := os.Getenv("DB_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			c.Database.Port = p
		}
	}
	if v := os.Getenv("DB_USER"); v != "" {
		c.Database.User = v
	}
	if v := os.Getenv("DB_PASSWORD"); v != "" {
		c.Database.Password = v
	}
	if v := os.Getenv("DB_NAME"); v != "" {
		c.Database.DBName = v
	}
	if v := os.Getenv("REDIS_HOST"); v != "" {
		c.Redis.Host = v
	}
	if v := os.Getenv("REDIS_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			c.Redis.Port = p
		}
	}
	if v := os.Getenv("DEEPSEEK_API_KEY"); v != "" {
		c.LLM.DeepSeek.APIKey = v
	}
	if v := os.Getenv("OPENAI_API_KEY"); v != "" {
		c.LLM.OpenAI.APIKey = v
	}
	if v := os.Getenv("OLLAMA_BASE_URL"); v != "" {
		c.LLM.Ollama.BaseURL = v
	}
}
