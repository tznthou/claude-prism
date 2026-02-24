---
command: ask-gemini
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

If code context is needed:
```bash
echo "$ARGUMENTS

Relevant code:
$(code content)" | ~/.claude/scripts/call-gemini.sh "review"
```

### 3. Present results

Show the Gemini response, clearly labeled **Gemini (3 Pro)**.

If Claude disagrees with any part of Gemini's answer, append Claude's own take so the user can compare both perspectives.

### Notes

- Works in any directory (no git repo required)
- Gemini excels at: broad ecosystem knowledge, alternative comparisons, Google-related tech
- Image/screenshot analysis: Gemini CLI headless mode does not support images — use Claude's own multimodal capability instead
