package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/argus-review/argus/internal/agent"
	"github.com/argus-review/argus/internal/config"
	"github.com/argus-review/argus/internal/llm"
	"github.com/argus-review/argus/internal/tool"
	"gopkg.in/yaml.v3"
)

func runReview(args []string) error {
	opts, err := parseReviewFlags(args)
	if err != nil {
		return fmt.Errorf("parse flags: %w", err)
	}
	if opts.showHelp {
		printReviewUsage()
		return nil
	}

	tpl, err := loadTemplate(opts.configPath)
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}
	if err := tpl.Validate(); err != nil {
		return fmt.Errorf("invalid config: %w", err)
	}

	repoDir, err := resolveRepoDir(opts.repoDir)
	if err != nil {
		return fmt.Errorf("resolve repo: %w", err)
	}

	llmClient := llm.NewClient(llm.ClientConfig{
		BaseURL: opts.llmBaseURL,
		APIKey:  opts.llmAPIKey,
		Model:   opts.llmModel,
		Timeout: opts.llmTimeout,
	})

	tools := buildToolRegistry()

	ag := agent.New(agent.Args{
		RepoDir:               repoDir,
		From:                  opts.from,
		To:                    opts.to,
		Commit:                opts.commit,
		Template:              *tpl,
		LLMClient:             llmClient,
		Tools:                 tools,
		MaxConcurrency:        opts.concurrency,
		PerFileTimeoutMinutes: opts.perFileTimeout,
		DryRun:                opts.dryRun,
	})

	ctx := context.Background()
	comments, err := ag.Run(ctx)
	if err != nil {
		return fmt.Errorf("review failed: %w", err)
	}

	if opts.outputFormat == "json" {
		return outputJSON(comments)
	}
	outputText(comments)

	return nil
}

// These helpers are shared between subcommands.

func loadTemplate(path string) (*config.Template, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config file %s: %w", path, err)
	}
	var tpl config.Template
	if err := yaml.Unmarshal(data, &tpl); err != nil {
		return nil, fmt.Errorf("unmarshal config: %w", err)
	}
	return &tpl, nil
}

func resolveRepoDir(input string) (string, error) {
	if input == "" {
		var err error
		input, err = os.Getwd()
		if err != nil {
			return "", fmt.Errorf("get working directory: %w", err)
		}
	}
	absPath, err := filepath.Abs(input)
	if err != nil {
		return "", fmt.Errorf("resolve absolute path: %w", err)
	}
	out, err := runGitCmd(absPath, "rev-parse", "--git-dir")
	if err != nil || len(out) == 0 {
		return "", fmt.Errorf("%s is not a git repository", absPath)
	}
	return absPath, nil
}

func buildToolRegistry() tool.Registry {
	reg := tool.NewRegistry()
	for _, t := range []tool.Tool{
		tool.FileRead, tool.FileFind, tool.FileReadDiff, tool.FileSearch, tool.CodeSearch,
	} {
		reg.Register(tool.NewStub(t))
	}
	return reg
}
