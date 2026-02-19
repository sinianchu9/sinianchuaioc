package config

import (
	"fmt"
	"os"
	"strconv"
	"time"

	"gopkg.in/yaml.v3"
)

// Config holds all configuration for the gateway service
type Config struct {
	Server    ServerConfig    `yaml:"server"`
	JWT       JWTConfig       `yaml:"jwt"`
	Database  DatabaseConfig  `yaml:"database"`
	Redis     RedisConfig     `yaml:"redis"`
	LLM       LLMConfig       `yaml:"llm"`
	RateLimit RateLimitConfig `yaml:"ratelimit"`
	Routing   RoutingConfig   `yaml:"routing"`
	Billing   BillingConfig   `yaml:"billing"`
}

type ServerConfig struct {
	GatewayPort int    `yaml:"gateway_port"`
	CorePort    int    `yaml:"core_port"`
	Mode        string `yaml:"mode"`
}

type JWTConfig struct {
	Secret             string        `yaml:"secret"`
	ExpireHours        int           `yaml:"expire_hours"`
	RefreshExpireHours int           `yaml:"refresh_expire_hours"`
	ExpireDuration     time.Duration `yaml:"-"`
	RefreshDuration    time.Duration `yaml:"-"`
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

type RateLimitConfig struct {
	RequestsPerMinute  int     `yaml:"requests_per_minute"`
	TokensPerMinute    int     `yaml:"tokens_per_minute"`
	CostLimitPerMinute float64 `yaml:"cost_limit_per_minute"`
	BurstSize          int     `yaml:"burst_size"`
}

type RoutingConfig struct {
	DefaultMode            string `yaml:"default_mode"`
	FallbackTimeoutSeconds int    `yaml:"fallback_timeout_seconds"`
}

type BillingConfig struct {
	FreeTokenQuota   int64   `yaml:"free_token_quota"`
	ProMonthlyPrice  float64 `yaml:"pro_monthly_price"`
}

// Load reads config from YAML file and overlays environment variables
func Load(path string) (*Config, error) {
	cfg := &Config{}

	// Read YAML file
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	// Override with environment variables
	cfg.overlayEnv()

	// Compute derived values
	cfg.JWT.ExpireDuration = time.Duration(cfg.JWT.ExpireHours) * time.Hour
	cfg.JWT.RefreshDuration = time.Duration(cfg.JWT.RefreshExpireHours) * time.Hour

	return cfg, nil
}

func (c *Config) overlayEnv() {
	if v := os.Getenv("GATEWAY_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			c.Server.GatewayPort = p
		}
	}
	if v := os.Getenv("CORE_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			c.Server.CorePort = p
		}
	}
	if v := os.Getenv("AIOC_MODE"); v != "" {
		c.Server.Mode = v
	}
	if v := os.Getenv("JWT_SECRET"); v != "" {
		c.JWT.Secret = v
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
	if v := os.Getenv("COST_LIMIT_PER_MIN"); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			c.RateLimit.CostLimitPerMinute = f
		}
	}
}
