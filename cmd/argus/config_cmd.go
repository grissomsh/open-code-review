package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Default config file location: ~/.argus/config.json
func defaultConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "argus.json"
	}
	return filepath.Join(home, ".argus", "config.json")
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

// Config represents the user-level configuration file (~/.argus/config.json).
type Config struct {
	Llm LlmConfig `json:"llm,omitempty"`
}

type LlmConfig struct {
	Provider string `json:"provider,omitempty"`
	URL      string `json:"url,omitempty"`
	Model    string `json:"model,omitempty"`
	Key      string `json:"key,omitempty"`
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

func setConfigValue(cfg *Config, key, value string) error {
	switch key {
	case "llm.provider", "llm.Provider":
		cfg.Llm.Provider = value
	case "llm.url", "llm.URL":
		cfg.Llm.URL = value
	case "llm.model", "llm.Model":
		cfg.Llm.Model = value
	case "llm.key", "llm.Key":
		cfg.Llm.Key = value
	default:
		return fmt.Errorf("unknown config key: %s\nSupported keys: llm.provider, llm.url, llm.model, llm.key", key)
	}
	return nil
}
