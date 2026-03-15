---
command: pi-askall
description: Ask both Codex and Gemini the same question — get three perspectives with Claude synthesis
---

# Ask All Providers

Send the same question to Codex and Gemini in parallel, then Claude synthesizes. **Multiple AI viewpoints on any topic — not limited to code.**

## Execution

### 1. Build the prompt

Use `$ARGUMENTS` as the base question.

**If `$ARGUMENTS` references a file path** (e.g., `src/config.ts` or `./README.md`):
- Read the file with the Read tool
- Append the file content as context to the question sent to both providers

**If `$ARGUMENTS` references recent conversation context** (e.g., "the plan we just discussed", "this approach"):
- Claude summarizes the relevant context into a self-contained question
- The question sent to providers must be understandable **without** conversation history

**If `$ARGUMENTS` is empty**, ask the user: "What topic or question should I get multiple perspectives on?"

### 2. Call Codex + Gemini in parallel

Use **two parallel Bash tool calls** with identical input to ensure independent perspectives.

Wrap the user's question:

```
Give your perspective on the following question. Be specific and direct — explain your reasoning, flag risks or tradeoffs you see, and suggest alternatives if relevant.

Question:
$ARGUMENTS (or the self-contained summary from Step 1)

$(if file/code context exists)
Context:
[file content or code]
$(end if)
```

**Codex:**
```bash
echo "$FRAMED_PROMPT" | ~/.claude/scripts/call-codex.sh "perspective request"
```

**Gemini:**
```bash
echo "$FRAMED_PROMPT" | ~/.claude/scripts/call-gemini.sh "perspective request"
```

The CLI argument (`"perspective request"`) is a short label for the call — the actual question is passed via stdin.

### 3. Handle partial failures

- One provider fails → continue with the other + Claude. Note which is absent.
- Both fail → Claude answers solo. Note: "External providers unavailable — single-perspective answer."
- **Never abort.** Always produce output.

### 4. Present provider responses

Show each provider's full response, clearly labeled:

```
### Codex
[full response]

### Gemini
[full response]
```

If a response is excessively long (>2000 words), summarize with key points and note that it was condensed.

### 5. Claude synthesis

Claude's role is **synthesizer** — compare, contrast, and judge the arguments. Claude has seen both responses and should be transparent about that rather than pretending to be an independent third voice.

#### Comparison table (when useful)

| Aspect | Codex | Gemini | Claude's take |
|--------|-------|--------|---------------|
| [key point] | ... | ... | ... |

Skip the table if the topic is too simple or the responses are too similar.

#### Consensus

Points where both providers agree — and whether Claude concurs or sees a blind spot they share.

#### Divergence

Points where providers disagree:
- State each position clearly
- Claude's judgment on which is stronger and **why**

#### Final take

Claude's integrated conclusion. Not a vote count — weigh arguments by reasoning quality. If the question is decision-oriented, end with a clear recommendation. If exploratory, end with open questions worth investigating.

### Notes

- Works with any topic: code, architecture, strategy, writing, decisions, plans
- Must be run inside a git repo if code context is needed (Codex CLI requirement)
- Keep injected context under 4000 chars per provider — summarize larger content
- For structured code review with confidence scoring, use `/pi-code-review` or `/pi-multi-review` instead
