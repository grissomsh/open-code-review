# OpenCodeReview CLI

AI-powered code review tool that reads Git diffs, sends changed files to a configurable LLM via OpenAI-compatible API, and generates structured review comments. It goes beyond surface-level analysis — the Agent can read project context for deep reviews.

## Install

```bash
tnpm install -g @ali/open-code-review
```

After installation, the `ocr` command is available globally.

### Version Control

```bash
# Install specific version
OCR_VERSION=v0.1.0 tnpm install -g @ali/open-code-review
```

## Prerequisites

**You must configure an LLM provider before using `ocr`.** The tool requires access to an OpenAI-compatible API endpoint (OpenAI, Claude, local models, etc.).

```bash
ocr config set llm.url https://your-api-endpoint/v1/chat/completions
ocr config set llm.auth_token your-api-key-here
ocr config set llm.model claude-opus-4-6
```

Or via environment variables:

```bash
export OCR_LLM_URL=https://your-api-endpoint/v1/chat/completions
export OCR_LLM_TOKEN=your-api-key-here
```

Config is stored in `~/.open-code-review/config.json`.

### Test Connectivity

```bash
ocr llm test
```

## Quick Start

Navigate to any Git repository and run:

```bash
# Review all workspace changes
ocr review

# Review diff between two branches
ocr review --from main --to feature-branch

# Review a single commit
ocr review --commit abc123
```

## Commands

| Command | Description |
|---------|-------------|
| `ocr review` / `ocr r` | Start code review |
| `ocr config set <key> <value>` | Manage configuration |
| `ocr llm test` | Test LLM connectivity |
| `ocr viewer` | Start WebUI session viewer |
| `ocr version` | Show version info |

## Common Options

| Flag | Shorthand | Default | Description |
|------|-----------|---------|-------------|
| `--repo` | | current dir | Git repository root |
| `--from` | | | Source ref (e.g., `main`) |
| `--to` | | | Target ref (e.g., `feature-branch`) |
| `--commit` | `-c` | | Review a single commit |
| `--format` | `-f` | `text` | Output format: `text` or `json` |
| `--concurrency` | | `4` | Max concurrent file reviews |
| `--timeout` | | `10` | Per-file timeout (minutes) |

## Features

- **Three review modes**: workspace changes, branch range, single commit
- **Context-aware**: Agent reads arbitrary files, searches code via `git grep`, inspects diffs
- **Plan phase**: Large changes (>50 lines) get risk analysis first
- **Any LLM**: Works with OpenAI, Claude-compatible endpoints, local models
- **Concurrent**: Files reviewed in parallel (configurable workers)

## License

Apache-2.0
