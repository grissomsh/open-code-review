package llm

import (
	"encoding/json"
	"strings"
)

// UsageInfo holds token usage extracted from an LLM API response.
type UsageInfo struct {
	TotalTokens int64 `json:"total_tokens"`
}

// totalTokensPaths is an ordered list of JSON paths to try when extracting
// total token count from a response body. Paths are dot-separated keys that
// navigate through nested map[string]any objects. The first match wins.
var totalTokensPaths = []string{
	"usage.total_tokens",      // OpenAI standard
	"total_tokens",            // flat at root
	"data.usage.total_tokens", // wrapped in data layer (some proxy APIs)
}

// resolveUsage parses raw JSON bytes into a map and extracts token usage
// by probing totalTokensPaths sequentially. Returns nil if no path matches.
func resolveUsage(raw []byte) *UsageInfo {
	var rawBody map[string]any
	if err := json.Unmarshal(raw, &rawBody); err != nil {
		return nil
	}

	total, ok := probePath(rawBody, totalTokensPaths)
	if !ok {
		return nil
	}
	return &UsageInfo{TotalTokens: total}
}

// probePath walks through each candidate path in order, returning the first
// int64 value found along with true. Returns (0, false) if none match.
func probePath(root map[string]any, paths []string) (int64, bool) {
	for _, p := range paths {
		parts := strings.Split(p, ".")

		var current any = root
		for _, part := range parts {
			obj, ok := current.(map[string]any)
			if !ok {
				goto next
			}
			current, ok = obj[part]
			if !ok {
				goto next
			}
		}

		switch v := current.(type) {
		case float64:
			return int64(v), true
		case int64:
			return v, true
		case int:
			return int64(v), true
		}
	next:
	}
	return 0, false
}
