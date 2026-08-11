---
command: pi-ask-codex
description: Ask Codex CLI a question — get OpenAI's perspective alongside Claude's
---

# Ask Codex

Forward the user's question to Codex CLI, get OpenAI's perspective.

## Execution

> **Bash invocation rules (v0.12.3+)**: Call `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with `timeout: 600000` (Bash tool's 10-minute ceiling). **Do not** use `&`, **do not** set `run_in_background: true`, **do not** use `nohup` — Claude Code 2026-04+ has an auto-background child-lifecycle regression that silently kills the process (output file stays 0 bytes). Use `run_in_background: true` + BashOutput polling only as an exception when the call is genuinely expected to exceed 10 minutes.

### 1. Build the prompt

Use `$ARGUMENTS` as the prompt. If the question involves project code, read relevant files with the Read tool and append them.

### 2. Call Codex

Wrap the question in the one-shot framing below (the framing prefix is fixed; `$ARGUMENTS` is the user's question verbatim):

```bash
CLAUDE_PRISM_TIMEOUT=300 CLAUDE_PRISM_CALLER=pi-ask-codex ~/.claude/scripts/call-codex.sh "You get exactly one turn: do not ask clarifying questions. If context is missing, state your assumptions and answer anyway. Lead with your answer, then reasoning. Be concise by default — expand only where the question demands depth.

Question:
$ARGUMENTS"
```

If code context is needed, pipe it via stdin (avoids ARG_MAX limits):
```bash
echo "Relevant code:
$(code content)" | CLAUDE_PRISM_TIMEOUT=300 CLAUDE_PRISM_CALLER=pi-ask-codex ~/.claude/scripts/call-codex.sh "You get exactly one turn: do not ask clarifying questions. If context is missing, state your assumptions and answer anyway. Lead with your answer, then reasoning. Be concise by default — expand only where the question demands depth.

Question:
$ARGUMENTS"
```

### 3. Handle failures

If Codex fails (script exits non-zero or CLI not found):
- Claude answers the question directly.
- Include the specific failure reason from stderr (the script classifies errors as TIMEOUT, RATE_LIMIT, AUTH_ERROR, SANDBOX, NETWORK, CLI_ERROR, or CLI_NOT_FOUND).
- Note in output: "⚠️ Codex unavailable ([reason]) — answering with Claude only. For multi-provider perspectives, try `/pi-askall`."

If the Bash tool was backgrounded or returned empty output, read the result from `~/.claude/logs/pi-codex-last.out` (persisted by the script's `tee` safety net).

### 4. Present results

Show the Codex response, clearly labeled **Codex**.

If Claude disagrees with any part of Codex's answer, append Claude's own take so the user can compare both perspectives.

### Notes

- Must be run inside a git repo (Codex CLI requirement)
- Codex excels at code-related questions but can handle general technical queries
- Keep injected code context under 4000 chars — summarize or extract relevant sections for larger files
