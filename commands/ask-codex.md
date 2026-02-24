---
command: ask-codex
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

If code context is needed:
```bash
~/.claude/scripts/call-codex.sh "$ARGUMENTS

Relevant code:
$(code content)"
```

### 3. Present results

Show the Codex response, clearly labeled **Codex**.

If Claude disagrees with any part of Codex's answer, append Claude's own take so the user can compare both perspectives.

### Notes

- Must be run inside a git repo (Codex CLI requirement)
- Codex excels at code-related questions but can handle general technical queries
