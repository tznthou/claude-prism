---
command: pi-askall
description: Ask both Codex and Gemini the same question — get three perspectives with Claude synthesis
---

# Ask All Providers

Send the same question to Codex and Gemini in parallel, then Claude synthesizes. **Multiple AI viewpoints on any topic — not limited to code.**

## Execution

> **Dispatch rules (v0.13.0+)**: For **parallel provider consultation**, use the `Agent` tool with `subagent_type: "general-purpose"` to spawn two parallel sub-agents — NOT two `Bash` tool calls in a single main-conversation response. Main-conversation Bash is a structural FIFO queue: the second Bash waits for the first to finish (`delta ≈ first_exec` precisely, measured N=7 across two capacity slots), which defeats the parallel intent. Sub-agent fan-out dispatches Bash calls truly in parallel (median delta 2.8s, N=13), saving roughly 28% wall-clock on a two-provider call.
>
> Inside each sub-agent, run `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with `timeout: 600000` (Bash tool's 10-minute ceiling). Do not use `&`, `nohup`, or `run_in_background: true` — Claude Code 2026-04+ has an auto-background child-lifecycle regression that silently kills the child (output file stays 0 bytes). If a sub-agent's Bash returns empty stdout, fall back to reading `~/.claude/logs/pi-{codex,gemini}-last.out` (the wrapper's `tee` safety net).

### 1. Build the prompt

Use `$ARGUMENTS` as the base question.

**If `$ARGUMENTS` references a file path** (e.g., `src/config.ts` or `./README.md`):
- Read the file with the Read tool
- Append the file content as context to the question sent to both providers

**If `$ARGUMENTS` references recent conversation context** (e.g., "the plan we just discussed", "this approach"):
- Claude summarizes the relevant context into a self-contained question
- The question sent to providers must be understandable **without** conversation history

**If `$ARGUMENTS` is empty**, ask the user: "What topic or question should I get multiple perspectives on?"

### 2. Frame the prompt, then fan out via sub-agents

**Step 2a — Build the framed wrapper** (compose once, used by both providers):

```
Give your perspective on the following question. Be specific and direct — explain your reasoning, flag risks or tradeoffs you see, and suggest alternatives if relevant.

Question:
$ARGUMENTS (or the self-contained summary from Step 1)

$(if file/code context exists)
Context:
[file content or code]
$(end if)
```

**Step 2b — Persist the framed prompt to a temp file** (shared by both sub-agents):

1. Bash: `PROMPT_FILE=$(mktemp -t prism-askall-XXXXXX.md) && echo "$PROMPT_FILE"` — capture the path.
2. Use the Write tool to write the framed prompt from Step 2a to that path.

**Step 2c — Send ONE response with two `Agent` tool calls in parallel.** Both use `subagent_type: "general-purpose"`. Fill `<PROMPT_FILE>` with the actual path from Step 2b.

**Codex agent** (description: "Codex perspective"):

```
Task: run one foreground-synchronous Bash command and return its output verbatim.

Step 1. Run this exact Bash command (timeout 600000 ms; no `&`, `nohup`, or `run_in_background: true`):

    start_ts=$(date +%s)
    cat <PROMPT_FILE> | ~/.claude/scripts/call-codex.sh "perspective request" 2>&1
    rc=$?
    end_ts=$(date +%s)
    echo "===META==="
    echo "rc=$rc"
    echo "runtime=$((end_ts - start_ts))s"
    echo "response_bytes=$(wc -c < ~/.claude/logs/pi-codex-last.out 2>/dev/null || echo NA)"

Step 2. If stdout is empty, Read `~/.claude/logs/pi-codex-last.out` — the wrapper's `tee` safety net persists the response there even when the Bash tool returns 0 bytes.

Step 3. Return to me: the complete stdout verbatim (do NOT summarize, paraphrase, or reformat the Codex response), the META block, and any stderr if rc != 0 (the wrapper classifies failures as TIMEOUT / RATE_LIMIT / AUTH_ERROR / SANDBOX / NETWORK / CLI_ERROR / CLI_NOT_FOUND).

Only use Bash and Read tools.
```

**Gemini agent** (description: "Gemini perspective"):

Same template as the Codex agent, with these substitutions:
- Replace `~/.claude/scripts/call-codex.sh` → `~/.claude/scripts/call-gemini.sh`
- Do NOT set or override `GEMINI_MODEL` — the user's environment passes through to the sub-agent's Bash, then to `call-gemini.sh`, then to the CLI. Skills do not pin model tiers on the user's behalf. If a call fails with RATE_LIMIT or capacity, surface the error and let the user decide whether to switch models.
- Fallback file: `~/.claude/logs/pi-gemini-last.out`
- Classifier list adds PERMISSION (Gemini-specific).

Both agents dispatch in parallel because they share a single main-conversation response. When both sub-agents return, proceed to Step 3. The CLI argument (`"perspective request"`) is a short label for the call — the actual question is passed via stdin from the temp file.

### 3. Handle partial failures

- One provider fails → continue with the other + Claude. Note which provider is absent and the specific failure reason from stderr (TIMEOUT, RATE_LIMIT, AUTH_ERROR, SANDBOX, PERMISSION, NETWORK, CLI_ERROR, or CLI_NOT_FOUND).
- Both fail → Claude answers solo. Note: "⚠️ Both external providers unavailable ([Codex reason] / [Gemini reason]) — single-perspective answer."
- **Never abort.** Always produce output.

If a sub-agent reported empty stdout, it should already have fallen back to reading `~/.claude/logs/pi-codex-last.out` or `~/.claude/logs/pi-gemini-last.out` (the wrapper's `tee` safety net). If even that file is 0 bytes, treat the provider as unavailable and note the failure reason in the output.

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
- Works outside git repos — Codex sandbox auto-downgrades to `none` for pure Q&A
- Keep injected context under 4000 chars per provider — summarize larger content
- For structured code review with confidence scoring, use `/pi-code-review` or `/pi-multi-review` instead
