package main

import (
	"fmt"
	"time"

	"github.com/argus-review/argus/internal/llm"
)

func runLLM(args []string) error {
	if len(args) == 0 {
		printLLMUsage()
		return nil
	}

	switch args[0] {
	case "test":
		return runLLMTest()
	default:
		return fmt.Errorf("unknown llm sub-command: %s\nRun 'argus llm' for usage", args[0])
	}
}

func runLLMTest() error {
	cfg, err := LoadAppConfig(defaultConfigPath())
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}
	if cfg == nil || cfg.Llm.URL == "" || cfg.Llm.AuthToken == "" {
		return fmt.Errorf("llm.url and llm.auth_token are required in %s", defaultConfigPath())
	}

	llmClient := llm.NewClient(llm.ClientConfig{
		URL:     cfg.Llm.URL,
		APIKey:  cfg.Llm.AuthToken,
		Model:   cfg.Llm.Model,
		Timeout: 30 * time.Second,
	})

	messages := []llm.Message{
		{Role: "user", Content: "你是谁？"},
	}

	resp, err := llmClient.GeneralRequest(messages, cfg.Llm.Model, nil)
	if err != nil {
		return fmt.Errorf("llm request failed: %w", err)
	}

	model := cfg.Llm.Model
	if resp.Model != "" {
		model = resp.Model
	}
	fmt.Printf("Model: %s\n", model)
	fmt.Printf("Content:\n%s\n", resp.Content())
	return nil
}

func printLLMUsage() {
	fmt.Println(`LLM utility commands.

Usage:
  argus llm <sub-command>

Sub-commands:
  test         Send a test message ("你是谁？") to the configured LLM model

Examples:
  argus llm test                 Verify LLM connectivity and configuration`)
}
