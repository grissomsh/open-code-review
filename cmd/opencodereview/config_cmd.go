package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
)

// Environment variable names that override config file values.
const (
	envLLMURL     = "OCR_LLM_URL"
	envLLMToken   = "OCR_LLM_TOKEN"
	envLLMModel   = "OCR_LLM_MODEL"
	envLanguage   = "OCR_LANGUAGE"
)

func envOrDefault(env, fallback string) string {
	if v := os.Getenv(env); v != "" {
		return v
	}
	return fallback
}

// LoadMergedConfig loads config from path, then overrides with environment variables if set.
// Returns nil, nil if file does not exist and no env vars are set.
func LoadMergedConfig(path string) (*Config, error) {
	cfg, err := LoadAppConfig(path)
	if err != nil {
		return nil, err
	}

	hasEnv := os.Getenv(envLLMURL) != "" || os.Getenv(envLLMToken) != "" ||
		os.Getenv(envLLMModel) != "" || os.Getenv(envLanguage) != ""
	if !hasEnv && cfg == nil {
		return nil, nil
	}
	if cfg == nil {
		cfg = &Config{}
	}

	if v := os.Getenv(envLLMURL); v != "" {
		cfg.Llm.URL = v
	}
	if v := os.Getenv(envLLMToken); v != "" {
		cfg.Llm.AuthToken = v
	}
	if v := os.Getenv(envLLMModel); v != "" {
		cfg.Llm.Model = v
	}
	if v := os.Getenv(envLanguage); v != "" {
		cfg.Language = v
	}

	return cfg, nil
}

// Default config file location: ~/.open-code-review/config.json
func defaultConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "open-code-review.json"
	}
	return filepath.Join(home, ".open-code-review", "config.json")
}

func runConfig(args []string) error {
	if len(args) == 0 {
		printConfigUsage()
		return nil
	}

	action, err := parseConfigArgs(args)
	if err != nil {
		return err
	}

	switch action.subCmd {
	case "set":
		return runConfigSet(action.key, action.value)
	default:
		return fmt.Errorf("unknown config sub-command: %s", action.subCmd)
	}
}

func runConfigSet(key, value string) error {
	configPath := defaultConfigPath()

	cfg, err := loadOrCreateConfig(configPath)
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	if err := setConfigValue(cfg, key, value); err != nil {
		return err
	}

	dir := filepath.Dir(configPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create config dir: %w", err)
	}

	data, err := json.MarshalIndent(cfg, "", "    ")
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}

	if err := os.WriteFile(configPath, data, 0o644); err != nil {
		return fmt.Errorf("write config: %w", err)
	}

	fmt.Printf("Set %s = %s\n", key, value)
	return nil
}

// Config represents the user-level configuration file (~/.open-code-review/config.json).
type Config struct {
	Llm       LlmConfig         `json:"llm,omitempty"`
	Language  string            `json:"language,omitempty"` // Output language, defaults to Chinese when empty
	Telemetry *TelemetryConfig  `json:"telemetry,omitempty"` // Telemetry/observability settings
}

type LlmConfig struct {
	Provider  string `json:"provider,omitempty"`
	URL     string `json:"url,omitempty"`
	AuthToken string `json:"auth_token,omitempty"`
	Model     string `json:"model,omitempty"`
}

// TelemetryConfig holds telemetry-specific settings.
type TelemetryConfig struct {
	Enabled      bool   `json:"enabled,omitempty"`       // Master switch for telemetry
	Exporter     string `json:"exporter,omitempty"`       // "console" or "otlp"
	OTLPEndpoint string `json:"otlp_endpoint,omitempty"` // OTLP collector address
	ContentLog   bool   `json:"content_logging,omitempty"` // Include prompt/response content
}

func loadOrCreateConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &Config{}, nil
		}
		return nil, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	return &cfg, nil
}

// LoadAppConfig loads config from path. Returns nil, nil if file does not exist.
func LoadAppConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read app config %s: %w", path, err)
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse app config: %w", err)
	}
	return &cfg, nil
}

func setConfigValue(cfg *Config, key, value string) error {
	switch key {
	case "llm.provider", "llm.Provider":
		cfg.Llm.Provider = value
	case "llm.url", "llm.URL":
		cfg.Llm.URL = value
	case "llm.auth_token", "llm.AuthToken":
		cfg.Llm.AuthToken = value
	case "llm.model", "llm.Model":
		cfg.Llm.Model = value
	case "language", "Language":
		cfg.Language = value
	case "telemetry.enabled", "telemetry.Enabled":
		b, err := strconv.ParseBool(value)
		if err != nil {
			return fmt.Errorf("invalid boolean for telemetry.enabled: %w", err)
		}
		cfg.ensureTelemetry()
		cfg.Telemetry.Enabled = b
	case "telemetry.exporter", "telemetry.Exporter":
		cfg.ensureTelemetry()
		cfg.Telemetry.Exporter = value
	case "telemetry.otlp_endpoint", "telemetry.OTLPEndpoint":
		cfg.ensureTelemetry()
		cfg.Telemetry.OTLPEndpoint = value
	case "telemetry.content_logging", "telemetry.ContentLog":
		b, err := strconv.ParseBool(value)
		if err != nil {
			return fmt.Errorf("invalid boolean for telemetry.content_logging: %w", err)
		}
		cfg.ensureTelemetry()
		cfg.Telemetry.ContentLog = b
	default:
		return fmt.Errorf("unknown config key: %s\nSupported keys: llm.provider, llm.url, llm.auth_token, llm.model, language, telemetry.enabled, telemetry.exporter, telemetry.otlp_endpoint, telemetry.content_logging", key)
	}
	return nil
}

func (c *Config) ensureTelemetry() {
	if c.Telemetry == nil {
		c.Telemetry = &TelemetryConfig{}
	}
}
