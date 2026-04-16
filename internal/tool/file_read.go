package tool

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// FileReadProvider reads file content at a given path and optional line range.
type FileReadProvider struct {
	RepoDir string
}

func (p *FileReadProvider) Tool() Tool { return FileRead }

func (p *FileReadProvider) Execute(args map[string]any) (string, error) {
	path, _ := args["path"].(string)
	if path == "" {
		return "Error: path is required", nil
	}

	startLine, _ := args["start_line"].(float64)
	endLine, _ := args["end_line"].(float64)
	if startLine <= 0 {
		startLine = 1
	}
	if endLine <= 0 {
		endLine = 200
	}

	fullPath := filepath.Join(p.RepoDir, path)
	content, err := os.ReadFile(fullPath)
	if err != nil {
		return fmt.Sprintf("Error: file %q not found: %v", path, err), nil
	}

	lines := strings.Split(string(content), "\n")
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("File: %s (lines %.0f-%.0f)\n", path, startLine, endLine))

	start := int(startLine) - 1
	end := int(endLine)
	if start >= len(lines) {
		return fmt.Sprintf("Error: file %q has only %d lines, requested range %d-%d", path, len(lines), int(startLine), int(endLine)), nil
	}
	if end > len(lines) {
		end = len(lines)
	}

	for i := start; i < end; i++ {
		sb.WriteString(fmt.Sprintf("%d|%s\n", i+1, lines[i]))
	}
	return sb.String(), nil
}
