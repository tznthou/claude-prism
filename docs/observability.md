# Observability

Everything claude-prism records locally about what it did — usage, review trends, invocation diagnostics, and a note on Claude Code's cache TTL behavior.

[繁體中文](observability.zh-TW.md) · [← Back to README](../README.md)

---

## Usage Summary

Track API call volume and estimated token consumption:

```bash
~/.claude/scripts/usage-summary.sh            # today
~/.claude/scripts/usage-summary.sh --week      # last 7 days
~/.claude/scripts/usage-summary.sh --all       # all time
~/.claude/scripts/usage-summary.sh --date 2026-02-24  # specific date
```

Output includes per-provider call counts, success/error/dry-run breakdown, and a rough token estimate (~4 chars/token).

## Review Insights

After each `/pi-code-review` or `/pi-multi-review`, Claude interprets the providers' output — mapping emoji severity to strings, inferring discovery source, filtering by the confidence threshold — and appends a structured record to `~/.claude/logs/review-insights.jsonl`. The script below reads that file with `jq` for raw counts; ask Claude to layer interpretation on top of the numbers:

```bash
~/.claude/scripts/review-insights.sh              # raw counts (no AI interpretation)
~/.claude/scripts/review-insights.sh --recent 10  # last 10 reviews
~/.claude/scripts/review-insights.sh --project my-app  # filter by project
```

Output includes:
- **Category distribution** — security, performance, design, logic, etc. (with bar chart)
- **Severity breakdown** — critical / medium / suggestion
- **Discovery source** — consensus vs. single-provider findings
- **Most frequent issues** — recurring patterns highlighted
- **Recent review timeline** — last 5 reviews with issue counts

Each review record follows this schema:

```json
{
  "date": "2026-02-24T10:30:00Z",
  "project": "my-app",
  "scope": "pr",
  "domain": "backend",
  "providers": ["codex", "gemini", "claude"],
  "issues": [
    {
      "category": "security",
      "severity": "critical",
      "confidence": 95,
      "title": "SQL injection in user input handler",
      "source": "consensus"
    }
  ]
}
```

Categories: `security`, `performance`, `design`, `logic`, `maintainability`, `guideline`, `accessibility`, `other`. The `guideline` category tracks violations of project-specific rules (`CLAUDE.md` / `Agents.md`).

## Invocation Diagnostics

When something goes wrong — a `/pi-*` command hangs, returns empty output, or a log file is unexpectedly 0 bytes — `analyze-log.sh` groups `multi-ai.log` events by pid and classifies each invocation's outcome:

```bash
~/.claude/scripts/analyze-log.sh              # analyze the default log
~/.claude/scripts/analyze-log.sh /path/to/log  # inspect a specific log file
```

Each invocation falls into one of five categories:

- **SUCCESS** — completed normally
- **ERROR** — the CLI returned non-zero (error class shown: `TIMEOUT`, `RATE_LIMIT`, `AUTH_ERROR`, `PERMISSION`, `SANDBOX`, `NETWORK`, `CLI_ERROR`, `CLI_NOT_FOUND`)
- **SIGNAL** — the script caught `HUP` / `INT` / `TERM` mid-run (the stage the script died at is recorded)
- **SOFT_TIMEOUT** (v0.14.0+) — the wrapper's `CLAUDE_PRISM_TIMEOUT` wall-clock guard fired; we killed the CLI with a structured marker, so this is distinguishable from the silent-death pattern below
- **SILENT** — invoked but produced no completion event — the signature of `SIGKILL`, commonly caused by Claude Code's Bash tool auto-backgrounding a call and killing its child

Silent deaths are the most actionable diagnostic signal: if you see one, your command was terminated before it could finish. The `pi-*` commands shipped in v0.12.3+ include a "Bash invocation rules" preamble that tells Claude to call scripts in foreground synchronous mode, bypassing this failure mode. See [CHANGELOG.md](../CHANGELOG.md) for the full regression writeup, and [Bash Tool Parallelism Research](research/bash-tool-parallelism.md) for the layered experiments behind the current design.

## Cache TTL Behavior

Claude Code currently uses a 5-minute prompt cache TTL for all subscribers — Pro and Max alike. When a `/pi-*` command takes longer than 5 minutes to return (Codex or Gemini occasionally runs past this window on complex tasks), the next turn in Claude Code pays full input price instead of reading from cache at the usual 10x discount.

This isn't a claude-prism bug — it reflects a Claude Code-wide shift from a 1-hour default back to 5 minutes around 2026-03-08 (see [GitHub issue #46829](https://github.com/anthropics/claude-code/issues/46829)). Anthropic's official [prompt caching documentation](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) does not gate TTL by subscription tier; community claims that Max subscribers automatically receive a 1-hour TTL remain unverified.

In practice, this overhead hasn't produced noticeable cost spikes for claude-prism users so far. If your usage pattern changes that, file an issue.
