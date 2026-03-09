---
command: pi-ask-codex
description: Ask Codex CLI a question — get OpenAI's perspective alongside Claude's
---

# Ask Codex

Forward the user's question to Codex CLI, get OpenAI's perspective.

## Execution

### 1. Build the prompt

Use `$ARGUMENTS` as the prompt. If the question involves project code, read relevant files with the Read tool and append them.

### 2. Call Codex

```bash
~/.claude/scripts/call-codex.sh "$ARGUMENTS"
```

If code context is needed, pipe it via stdin (avoids ARG_MAX limits):
```bash
echo "Relevant code:
$(code content)" | ~/.claude/scripts/call-codex.sh "$ARGUMENTS"
```

### 3. Handle failures

If Codex fails (script exits non-zero or CLI not found), Claude answers the question directly and notes: "Codex unavailable — answering with Claude only."

### 4. Present results

Show the Codex response, clearly labeled **Codex**.

If Claude disagrees with any part of Codex's answer, append Claude's own take so the user can compare both perspectives.

### Notes

- Must be run inside a git repo (Codex CLI requirement)
- Codex excels at code-related questions but can handle general technical queries
- Keep injected code context under 4000 chars — summarize or extract relevant sections for larger files
