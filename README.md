# OpenCodeReview

一个基于 Go 开发的 AI 代码审查 CLI 工具。OpenCodeReview 读取 Git Diff，将变更文件通过 OpenAI 兼容 API 发送给可配置的 LLM，生成结构化的代码审查评论 —— 它不仅分析 diff 表面变更，还能自主阅读项目上下文进行深度审查。

## 核心特性

- **三种审查模式**：工作区变更（默认）、分支范围（`--from` / `--to`）、单次提交（`--commit`）
- **上下文感知**：LLM Agent 可以读取任意文件、使用 `git grep` 搜索代码、查看 diff 差异 —— 超越表面的行级分析
- **Plan 阶段**：当文件变更超过阈值（默认 50 行），Agent 先产出风险分析计划，识别严重程度和建议操作
- **记忆压缩**：对话 token 数超过阈值（~50K）时自动压缩历史上下文，防止长会话超出模型窗口
- **并发执行**：每个文件独立并行审查（可配置并发数，默认 4 worker）
- **异步评论处理**：CommentWorkerPool 对 review comment 进行后处理（行号追踪、建议验证等），不阻塞主循环
- **自定义规则**：基于 glob 的系统规则，按语言或路径应用不同的审查标准
- **完整可观测性**：内置 OpenTelemetry，支持 OTLP gRPC 和 stdout 导出器
- **兼容任何 LLM**：支持 OpenAI、Claude（兼容端点）、本地模型等

## 安装

### 从源码构建

需要 [Go](https://go.dev/) 1.25+。

```bash
git clone https://github.com/open-code-review/open-code-review.git
cd open-code-review
make        # 编译到 ./dist/opencodereview
```

或直接构建：

```bash
go build -o bin/opencodereview ./cmd/opencodereview
```

### 跨平台构建

Makefile 提供了跨平台构建目标：

```bash
make build-linux-amd64
make build-linux-arm64
make build-darwin-amd64
make build-darwin-arm64
make build-all          # 构建所有平台
```

将生成的 binary 加入 `$PATH`：

```bash
cp dist/opencodereview /usr/local/bin/ocr
```

## 快速开始

### 1. 配置 LLM

OpenCodeReview 支持连接任何 OpenAI 兼容的 API 端点。有两种配置方式：

**配置文件**（推荐）：

```bash
ocr config set llm.url https://your-api-endpoint/v1/chat/completions
ocr config set llm.auth_token your-api-key-here
ocr config set llm.model claude-opus-4-6
```

**环境变量**：

```bash
export OCR_LLM_URL=https://your-api-endpoint/v1/chat/completions
export OCR_LLM_TOKEN=your-api-key-here
```

配置存储在 `~/.open-code-review/config.json`。

### 2. 测试连通性

```bash
ocr llm test
```

### 3. 运行审查

进入任意 Git 仓库目录并运行：

```bash
# 审查所有已暂存、未暂存和未跟踪的变更
ocr review

# 审查两个分支之间的差异
ocr review --from main --to feature-branch

# 审查特定提交
ocr review --commit abc123
```

## 使用方式

### 命令

| 命令 | 描述 |
|------|------|
| `ocr review` / `ocr r` | 启动代码审查 |
| `ocr config set <key> <value>` | 管理用户配置 |
| `ocr llm test` | 测试 LLM 连通性 |
| `ocr version` | 显示版本信息 |

### 审查参数

| 参数 | 简写 | 默认值 | 描述 |
|------|------|--------|------|
| `--repo` | | 当前目录 | Git 仓库根目录 |
| `--from` | | | 起始引用（如 `main`） |
| `--to` | | | 目标引用（如 `feature-branch`） |
| `--commit` | `-c` | | 要审查的单次提交（对比其父提交） |
| `--format` | `-f` | `text` | 输出格式：`text` 或 `json` |
| `--concurrency` | | `4` | 最大并发文件审查数 |
| `--timeout` | | `10` | 单文件超时时间（分钟） |
| `--rule` | | | 自定义系统规则的 JSON 文件路径 |
| `--tools` | | 内嵌默认 | 工具定义的 JSON 文件路径（省略则使用内嵌默认值） |

### 审查模式详解

**工作区模式**（无参数）：审查当前工作区所有已暂存、未暂存和未跟踪的变更。

```bash
ocr review
```

**分支范围模式**：使用 merge-base 计算两个 git 引用之间的差异。

```bash
ocr review --from main --to dev
```

**单次提交模式**：对比某次提交与其父提交的差异。

```bash
ocr review --commit abc123
```

## 配置

### 配置文件

位于 `~/.open-code-review/config.json`：

```json
{
  "llm": {
    "url": "https://api.anthropic.com/v1/messages",
    "auth_token": "your-api-key",
    "model": "claude-opus-4-6"
  },
  "language": "Chinese"
}
```

| 字段 | 说明 | 示例 |
|------|------|------|
| `llm.url` | OpenAI 兼容 API 端点 | `https://api.openai.com/v1/chat/completions` |
| `llm.auth_token` | API Key / 认证 Token | `sk-xxx...` |
| `llm.model` | 模型标识 | `gpt-4o`, `claude-opus-4-6` |
| `language` | 偏好响应语言 | `zh-CN`, `en-US` |

### 环境变量

与配置文件等效的环境变量：

| 环境变量 | 对应配置字段 |
|----------|--------------|
| `OCR_LLM_URL` | `llm.url` |
| `OCR_LLM_TOKEN` | `llm.auth_token` |

## 工作原理

```
┌──────────────┐
│  加载 Diff    │ 解析 git unified diff 为结构化文件变更
└──────┬───────┘
       ▼
┌──────────────┐
│ Plan 阶段     │ 大变更文件（>50 行）先由 LLM 产出风险分析计划，
│ （可选）      │ 标注严重级别和建议操作；小变更跳过此步
└──────┬───────┘
       ▼
┌──────────────┐
│ 主循环        │ 多轮 LLM 对话 —— Agent 调用工具读取文件、搜索代码、
│              │ 检查 diff 并提交审查评论
└──────┬───────┘
       ▼
┌──────────────┐
│ 记忆压缩      │ 当上下文超 ~50K token 时，自动压缩历史对话
└──────┬───────┘
       ▼
┌──────────────┐     ┌──────────────┐
│   输出        │ 收集的评论以 text 或 json 格式渲染
└──────────────┘
```

每个变更文件作为独立子任务并发执行。完整的会话历史（请求、响应、工具调用、耗时、token 估算）保存至 `<仓库>/temp/ocr-session-*.json`，方便调试。

## Agent 工具列表

审查过程中，LLM Agent 可以使用以下工具：

| 工具 | 描述 |
|------|------|
| `file_read` | 读取指定路径的文件内容（支持行范围，单次最多 500 行） |
| `file_find` | 按名称模式在仓库中查找文件（跳过 node_modules、vendor、.idea 等） |
| `code_search` | 使用 `git grep` 搜索代码内容（支持正则、大小写忽略、文件模式过滤） |
| `file_read_diff` | 读取指定文件的 diff |
| `code_comment` | 提交审查评论，包含建议代码、行范围和理由 |
| `task_done` | 标记该文件的审查完成 |

## 可调参数

以下参数定义了 Agent 的行为边界，可在运行时调整（部分通过环境变量）：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `PLAN_MODE_LINE_THRESHOLD` | 50 | 触发 Plan 阶段的文件变更行数阈值 |
| `MAX_TOKENS` | 58888 | 大模型请求的最大 token 数限制，内部阈值为该值的 80%（用于警告和记忆压缩） |
| `MAX_TOOL_REQUEST_TIMES` | 20 | 每个文件的最大工具调用次数 |
| `TOOL_REQUEST_WAIT_TIME_MS` | 10000 | 工具调用等待时间（毫秒） |
| `MAX_SUBTASK_EXECUTION_TIME_MINUTES` | 5 | 单个子任务最长执行时间（分钟） |

## 可观测性

OpenCodeReview 内置 [OpenTelemetry](https://opentelemetry.io/) 集成，提供全链路监控和指标采集：

- **Traces**：记录每次审查会话的完整生命周期，包括 diff 加载、plan 阶段、主循环迭代、工具调用和输出生成
- **Metrics**：统计审查持续时间、生成的评论数、token 消耗等关键指标
- **Exporter**：支持 OTLP gRPC 导出器和 stdout 导出器，可对接 Jaeger、Grafana Tempo 等后端

## 项目结构

```
├── cmd/opencodereview/       # CLI 入口和命令分发
│   ├── main.go               # 应用入口
│   ├── review_cmd.go         # 审查编排核心
│   ├── flags.go              # 参数解析
│   ├── config_cmd.go         # 配置管理子命令
│   ├── llm_cmd.go            # LLM 工具命令
│   ├── output.go             # 输出格式化（text/json）
│   └── git.go                # Git 辅助函数
│
├── internal/
│   ├── agent/agent.go        # Agent 编排器：diff 加载 → plan → 主循环 → 记忆压缩
│   ├── config/               # 内嵌配置模板、规则、工具定义
│   ├── diff/                 # Git diff 解析和行号映射
│   ├── llm/                  # OpenAI 兼容 LLM HTTP 客户端
│   ├── model/                # 数据模型
│   ├── session/              # 会话历史追踪
│   ├── telemetry/            # OpenTelemetry 集成
│   └── tool/                 # 工具实现（file_read、code_search、code_comment 等）
│
├── pkg/                      # 公共包导出
├── Makefile                  # 构建系统（含跨平台目标）
└── go.mod                    # Go 模块依赖
```
