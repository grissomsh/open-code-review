package config

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// SystemRule holds review rules loaded from an external JSON config.
type SystemRule struct {
	DefaultRule string            `json:"default_rule"`
	PathRuleMap map[string]string `json:"path_rule_map"`
}

// Resolve returns the rule text for a given file path.
// It matches against PathRuleMap keys using filepath.Match glob patterns.
// The first match wins; if none match, it falls back to DefaultRule.
func (r *SystemRule) Resolve(path string) string {
	for pattern, rule := range r.PathRuleMap {
		if matched, _ := filepath.Match(pattern, path); matched {
			return rule
		}
	}
	return r.DefaultRule
}

// Template holds the native agent task template configuration.
// Mirrors NativeAgentTemplate from the Java implementation, loaded via JSON at runtime.
type Template struct {
	MainTask              LlmConversation  `json:"MAIN_TASK"`
	PlanTask              *LlmConversation `json:"PLAN_TASK,omitempty"`
	MemoryCompressionTask LlmConversation  `json:"MEMORY_COMPRESSION_TASK"`
	TokenWarningThreshold int              `json:"TOKEN_WARNING_THRESHOLD"`
	ToolRequestWaitTimeMs int              `json:"TOOL_REQUEST_WAIT_TIME_MS"`
	MaxToolRequestTimes   int              `json:"MAX_TOOL_REQUEST_TIMES"`
	MaxSubtaskExecMinutes int              `json:"MAX_SUBTASK_EXECUTION_TIME_MINUTES"`
}

//go:embed task_template.json
var defaultTemplate []byte

//go:embed tools.json
var defaultToolsJSON []byte

//go:embed system_rules.json
var defaultSystemRules []byte

// LoadDefaultSystemRule parses the embedded system_rules.json.
func LoadDefaultSystemRule() (*SystemRule, error) {
	var rule SystemRule
	if err := json.Unmarshal(defaultSystemRules, &rule); err != nil {
		return nil, fmt.Errorf("unmarshal default system rules: %w", err)
	}
	return &rule, nil
}

// LoadTemplate parses the embedded task_template.json as the default template.
func LoadTemplate() (*Template, error) {
	var tpl Template
	if err := json.Unmarshal(defaultTemplate, &tpl); err != nil {
		return nil, fmt.Errorf("unmarshal default template: %w", err)
	}
	return &tpl, nil
}

// Validate checks required template fields.
func (t *Template) Validate() error {
	if t.TokenWarningThreshold <= 0 {
		return fmt.Errorf("token_warning_threshold must be positive")
	}
	if t.MaxToolRequestTimes <= 0 {
		return fmt.Errorf("max_tool_request_times must be positive")
	}
	if len(t.MainTask.Messages) == 0 {
		return fmt.Errorf("main_task.messages must not be empty")
	}
	return nil
}

// LlmConversation mirrors LlmConversation from the Java side — a preset prompt with settings.
type LlmConversation struct {
	Timeout  int           `json:"timeout"`
	Messages []ChatMessage `json:"messages"`
}

// ChatMessage represents a single message in a conversation.
type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ToolConfigEntry holds a single tool definition loaded from tools.json.
type ToolConfigEntry struct {
	Name       string          `json:"name"`
	PlanTask   bool            `json:"plan_task"`
	MainTask   bool            `json:"main_task"`
	Definition json.RawMessage `json:"definition"`
}

// LoadTools parses the tools config file. When path is empty, falls back to
// the embedded default tools configuration.
func LoadTools(path string) ([]ToolConfigEntry, error) {
	var data []byte
	var err error
	if path == "" {
		data = defaultToolsJSON
	} else {
		data, err = os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read tools file %s: %w", path, err)
		}
	}
	var tools []ToolConfigEntry
	if err := json.Unmarshal(data, &tools); err != nil {
		return nil, fmt.Errorf("unmarshal tools file: %w", err)
	}
	return tools, nil
}

// ToolDefsByPhase returns the parsed tool definitions filtered by phase.
// planOnly=true returns only tools with plan_task:true.
// planOnly=false returns only tools with main_task:true.
func (t *ToolConfigEntry) ToolDefsByPhase(planOnly bool) (json.RawMessage, bool) {
	switch {
	case planOnly && t.PlanTask:
		return t.Definition, true
	case !planOnly && t.MainTask:
		return t.Definition, true
	default:
		return nil, false
	}
}
