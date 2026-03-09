---
command: pi-ask-gemini
description: Ask Gemini CLI a question — get Google's perspective alongside Claude's
---

# Ask Gemini

Forward the user's question to Gemini CLI, get Google's perspective.

## Execution

### 1. Build the prompt

Use `$ARGUMENTS` as the prompt. If the question involves project code, read relevant files with the Read tool and append them.

### 2. Call Gemini

```bash
~/.claude/scripts/call-gemini.sh "$ARGUMENTS"
```

If code context is needed, pipe it via stdin (avoids ARG_MAX limits):
```bash
echo "Relevant code:
$(code content)" | ~/.claude/scripts/call-gemini.sh "$ARGUMENTS"
```

### 3. Handle failures

If Gemini fails (script exits non-zero or CLI not found), Claude answers the question directly and notes: "Gemini unavailable — answering with Claude only."

### 4. Present results

Show the Gemini response, clearly labeled **Gemini**.

If Claude disagrees with any part of Gemini's answer, append Claude's own take so the user can compare both perspectives.

### Notes

- Works in any directory (no git repo required)
- Gemini excels at: broad ecosystem knowledge, alternative comparisons, Google-related tech
- Image/screenshot analysis: Gemini CLI headless mode does not support images — use Claude's own multimodal capability instead
- Keep injected code context under 4000 chars — summarize or extract relevant sections for larger files
