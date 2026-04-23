---
command: pi-plan
description: "Multi-provider implementation planning — consult Codex and Gemini for architectural perspectives. Trigger: when the task involves architectural decisions, tech stack selection, evaluating multiple approaches, migration strategy, or complex implementation with multiple viable paths. Do NOT trigger for simple task breakdown, step-by-step instructions, or when the user just wants to 'think through' something — use Claude's built-in plan mode for those."
---

# Plan Generation

Analyze the codebase and generate a structured implementation plan with cross-provider architectural consultation. Use this when **multiple viable approaches exist** and external perspectives add value — not for simple task breakdown.

## Execution

> **Dispatch rules (v0.13.0+)**: For **parallel provider consultation**, use the `Agent` tool with `subagent_type: "general-purpose"` to spawn two parallel sub-agents — NOT two `Bash` tool calls in a single main-conversation response. Main-conversation Bash is a structural FIFO queue: the second Bash waits for the first to finish (`delta ≈ first_exec` precisely, measured N=7 across two capacity slots), which defeats the parallel intent. Sub-agent fan-out dispatches Bash calls truly in parallel (median delta 2.8s, N=13), saving roughly 28% wall-clock on a two-provider call.
>
> Inside each sub-agent, run `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with `timeout: 600000` (Bash tool's 10-minute ceiling). Do not use `&`, `nohup`, or `run_in_background: true` — Claude Code 2026-04+ has an auto-background child-lifecycle regression that silently kills the child (output file stays 0 bytes). If a sub-agent's Bash returns empty stdout, fall back to reading `~/.claude/logs/pi-{codex,gemini}-last.out` (the wrapper's `tee` safety net).

### 1. Parse arguments

`$ARGUMENTS` is the task description. If it's too vague (less than ~10 words and no clear objective), use AskUserQuestion to clarify:
- What is the desired end state?
- Are there constraints (tech stack, scope)?
- Should external providers be consulted? (default: yes if available)

### 2. Analyze the codebase

Use Read, Glob, and Grep tools to understand the current state:
- Project structure and key directories
- Relevant existing code (files related to the task)
- Dependencies and configuration
- Existing tests and CI setup

### 3. Detect domain

If there are existing files that will be modified, detect the domain:

```bash
echo "<list of relevant files, one per line>" | ~/.claude/scripts/detect-domain.sh
```

If the task is greenfield (no existing files to modify), infer domain from the task description:
- UI/design/component/style keywords → `frontend`
- API/database/auth/algorithm keywords → `backend`
- Mixed or unclear → `fullstack`

If the script is not found, infer manually and continue.

### 4. Consult external providers (optional, parallel via sub-agent fan-out)

If both providers are available, consult them in parallel for independent analysis. **Sub-agent fan-out required** — see Dispatch rules above for why main-conversation parallel Bash does NOT work here.

**Step 4a — Build the shared architect prompt** (used by both providers):

```
You are a software architect. Analyze this task and provide:
1. Key technical challenges
2. Recommended approach (with alternatives considered)
3. Potential risks and edge cases
4. Estimated complexity (S/M/L/XL)

Task: $ARGUMENTS

Relevant codebase context:
$(relevant code snippets — the temp-file dispatch removes the old shell ARG_MAX constraint, so brevity here is a quality heuristic, not a transport limit. Prioritize signal density: include the files / areas directly impacted by the task, skip peripheral or pre-existing code unless the architect needs it for context)
```

**Step 4b — Persist the prompt to a temp file**:

1. Bash: `PROMPT_FILE=$(mktemp -t prism-plan-XXXXXX.md) && echo "$PROMPT_FILE"` — capture the path.
2. Use the Write tool to write the architect prompt from Step 4a to that path.

**Step 4c — Send ONE response with two `Agent` tool calls in parallel.** Both use `subagent_type: "general-purpose"`. Fill `<PROMPT_FILE>` with the actual path from Step 4b.

**Codex agent** (description: "Codex architect perspective"):

```
Task: run one foreground-synchronous Bash command and return its output verbatim.

Step 1. Run this exact Bash command (timeout 600000 ms; no `&`, `nohup`, or `run_in_background: true`):

    start_ts=$(date +%s)
    wrapper_out=$(~/.claude/scripts/call-codex.sh "architect review" < "<PROMPT_FILE>" 2>&1)
    rc=$?
    end_ts=$(date +%s)
    if [ -z "$wrapper_out" ]; then
        wrapper_out=$(cat ~/.claude/logs/pi-codex-last.out 2>/dev/null)
        [ -n "$wrapper_out" ] && echo "[FALLBACK: wrapper stdout was empty — loaded from pi-codex-last.out]"
    fi
    printf '%s\n' "$wrapper_out"
    echo "===META==="
    echo "rc=$rc"
    echo "runtime=$((end_ts - start_ts))s"
    echo "response_bytes=$(wc -c < ~/.claude/logs/pi-codex-last.out 2>/dev/null || echo NA)"

Two design notes on this Bash shape:
- `< "<PROMPT_FILE>"` feeds the prompt directly to the wrapper's stdin — NO `cat |` pipe. Without `set -o pipefail`, a pipeline's `$?` is only the tail command's exit code, so a missing / unreadable prompt file would silently run the wrapper on empty stdin. Direct redirect keeps `$?` as the wrapper's real rc.
- The `wrapper_out` capture lets the emptiness check run BEFORE the META block is printed. If we echoed META first, stdout would never be empty (META would always fill it), so the `pi-codex-last.out` fallback for silent-kill / auto-bg regressions would never trigger.

Step 2. Return to me: the complete printed output verbatim (do NOT summarize, paraphrase, or reformat the Codex response), including the META block. If the Bash command printed a `[FALLBACK: ...]` line, relay that too — it signals the wrapper was silently killed and the response came from the tee safety net. If rc != 0, include any stderr — the wrapper classifies failures as TIMEOUT / RATE_LIMIT / AUTH_ERROR / SANDBOX / NETWORK / CLI_ERROR / CLI_NOT_FOUND.

Only use Bash and Read tools.
```

**Gemini agent** (description: "Gemini architect perspective"):

Same template as the Codex agent, with these substitutions:
- Replace `~/.claude/scripts/call-codex.sh` → `~/.claude/scripts/call-gemini.sh`
- Do NOT set or override `GEMINI_MODEL` in the Bash command — the user's environment passes through to the sub-agent, then to `call-gemini.sh`, then to the CLI. Skills do not pin model tiers on the user's behalf.
- Fallback file: `~/.claude/logs/pi-gemini-last.out`
- Classifier list adds PERMISSION (Gemini-specific) and has no SANDBOX.

Both agents dispatch in parallel because they share a single main-conversation response. When both return, proceed to Step 5.

### 5. Handle partial failures (graceful degradation)

- If one provider fails → continue with the other + Claude. Include the specific failure reason from stderr (TIMEOUT, RATE_LIMIT, AUTH_ERROR, SANDBOX, PERMISSION, NETWORK, CLI_ERROR, or CLI_NOT_FOUND). Note: "⚠️ [Provider] unavailable ([reason]) — plan informed by [other provider] + Claude."
- If both fail → Claude generates the plan solo. Note: "⚠️ Both providers unavailable ([Codex reason] / [Gemini reason]) — plan generated by Claude only."
- Always note which providers contributed in the plan file.

If a sub-agent reported empty stdout, it should already have fallen back to reading `~/.claude/logs/pi-codex-last.out` or `~/.claude/logs/pi-gemini-last.out` (the wrapper's `tee` safety net). If even that file is 0 bytes, treat the provider as unavailable and record the failure reason in the plan's Metadata section.

### 6. Synthesize and generate plan file

Combine all perspectives (Claude's own analysis + any external input) into a structured plan.

**Slugify the task name**: lowercase, replace spaces/special chars with hyphens, max 50 chars. If a file with the same slug already exists, append `-2`, `-3`, etc.

**Create the plan file using Bash tool:**

```bash
mkdir -p .claude/pi-plans
cat > ".claude/pi-plans/<slug>.md" << 'PLAN_EOF'
# Plan: <task name>

## Metadata
- **Generated**: <ISO 8601 UTC timestamp>
- **Domain**: <frontend | backend | fullstack>
- **Status**: draft
- **Providers consulted**: <codex, gemini | codex | gemini | claude-only>

## Context
<Why this change is needed — synthesized from $ARGUMENTS and codebase analysis>

## Analysis
### Codex Perspective
<Codex analysis, or "Not consulted" / "Unavailable">

### Gemini Perspective
<Gemini analysis, or "Not consulted" / "Unavailable">

### Synthesis
<Where providers agree/disagree, Claude's judgment on conflicts, chosen approach>

## Steps
- [ ] <Step description> — <expected outcome>
- [ ] <Step description> — <expected outcome>
...

## Key Files
| File | Action | Notes |
|------|--------|-------|
| path/to/file | create/modify/delete | description |

## Risks
| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| description | low/medium/high | how to handle |

## Verification
- [ ] <How to verify the implementation>
- [ ] <Acceptance criteria>
PLAN_EOF
```

### 7. Output

After creating the file, tell the user:
1. The plan file path
2. A brief summary of the plan (key approach, step count, domain)
3. Instruction: "Review the plan, then ask Claude Code to implement it step by step."

**CRITICAL: Do NOT auto-execute.** The plan command ends here. The user decides when to execute.

### Notes

- Plans are stored in the project's `.claude/pi-plans/` directory (project-local, not global)
- The `.claude/pi-plans/` directory is for working documents — users should consider gitignoring it
- If external provider consultation would not add value for a trivial task, skip Step 4 and note "Providers not consulted (task too small to benefit from multi-perspective analysis)"
