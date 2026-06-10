---
command: pi-ask-gemini
description: Ask Gemini a question — get Google's perspective alongside Claude's
---

# Ask Gemini

Forward the user's question to Gemini (via agy, the Antigravity CLI), get Google's perspective.

## Execution

> **Bash invocation rules (v0.12.3+)**: Call `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with `timeout: 600000` (Bash tool's 10-minute ceiling). **Do not** use `&`, **do not** set `run_in_background: true`, **do not** use `nohup` — Claude Code 2026-04+ has an auto-background child-lifecycle regression that silently kills the process (output file stays 0 bytes). Use `run_in_background: true` + BashOutput polling only as an exception when the call is genuinely expected to exceed 10 minutes.

### 1. Build the prompt

Use `$ARGUMENTS` as the prompt. If the question involves project code, read relevant files with the Read tool and append them.

### 2. Call Gemini

```bash
CLAUDE_PRISM_TIMEOUT=300 CLAUDE_PRISM_CALLER=pi-ask-gemini ~/.claude/scripts/call-gemini.sh "$ARGUMENTS"
```

If code context is needed, pipe it via stdin (avoids ARG_MAX limits):
```bash
echo "Relevant code:
$(code content)" | CLAUDE_PRISM_TIMEOUT=300 CLAUDE_PRISM_CALLER=pi-ask-gemini ~/.claude/scripts/call-gemini.sh "$ARGUMENTS"
```

### 3. Handle failures

If Gemini fails (script exits non-zero or CLI not found):
- Claude answers the question directly.
- Include the specific failure reason from stderr (the script classifies errors as TIMEOUT, RATE_LIMIT, AUTH_ERROR, PERMISSION, NETWORK, EMPTY_OUTPUT, CLI_ERROR, or CLI_NOT_FOUND).
- Note in output: "⚠️ Gemini unavailable ([reason]) — answering with Claude only. For multi-provider perspectives, try `/pi-askall`."

If the Bash tool was backgrounded or returned empty output, read the result from `~/.claude/logs/pi-gemini-last.out` (persisted by the script's `tee` safety net).

### 4. Present results

Show the Gemini response, clearly labeled **Gemini**.

If Claude disagrees with any part of Gemini's answer, append Claude's own take so the user can compare both perspectives.

### Notes

- Works in any directory (no git repo required)
- Gemini excels at: broad ecosystem knowledge, alternative comparisons, Google-related tech
- Image/screenshot analysis: agy headless mode does not support images — use Claude's own multimodal capability instead
- Keep injected code context under 4000 chars — summarize or extract relevant sections for larger files
