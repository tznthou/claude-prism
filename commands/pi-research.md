---
command: pi-research
description: Technical research via Gemini + WebSearch — dual-track search with Claude synthesis
---

# Technical Research (Dual-Track)

Research topics using Gemini (Google search grounding) and WebSearch in parallel, then Claude synthesizes. **Two search tracks ensure resilience — if one fails, the other covers.**

## Execution

> **Bash invocation rules (v0.12.3+)**: Call `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with `timeout: 600000` (Bash tool's 10-minute ceiling). **Do not** use `&`, **do not** set `run_in_background: true`, **do not** use `nohup` — Claude Code 2026-04+ has an auto-background child-lifecycle regression that silently kills the process (output file stays 0 bytes). Use `run_in_background: true` + BashOutput polling only as an exception when the call is genuinely expected to exceed 10 minutes.

### 1. Understand the research topic

`$ARGUMENTS` is the research topic. If the topic is vague, clarify with AskUserQuestion:
- Research purpose (tech selection? learning? problem solving?)
- Depth needed (quick overview vs deep analysis)
- Constraints (tech stack, budget, team size)

### 2. Gather project context (if relevant)

If the research topic relates to the current project, use Read/Glob/Grep to collect relevant context (dependencies, existing patterns, config). Keep context under 4000 chars — summarize if needed.

### 3. Dual-track research

Launch **both tracks simultaneously** in a single response:

```
                    ┌─ Track A: Gemini (search grounding) ─┐
  Research topic ──→│                                       │──merge──→ Step 5
                    └─ Track B: WebSearch (targeted queries)─┘
```

#### Track A — Gemini

Use the Bash tool with timeout parameter (90 seconds):

```bash
# Use Bash tool with timeout: 90000
echo "$PROJECT_CONTEXT" | CLAUDE_PRISM_TIMEOUT=300 CLAUDE_PRISM_CALLER=pi-research ~/.claude/scripts/call-gemini.sh "You are a technical researcher. Conduct in-depth research.

Research topic: $ARGUMENTS

Please provide:
1. Topic overview (one-paragraph summary)
2. Mainstream solution comparison (table format with pros/cons)
3. Recommended approach and reasoning
4. Common pitfalls and caveats
5. Recommended resources (official docs, tutorials, GitHub repos)
6. Source URLs for key claims (one per line)

If this involves tech selection, compare at least 3 options across these dimensions:
- Learning curve
- Community activity
- Performance
- Ecosystem
- Use cases"
```

If no project context, omit the stdin pipe.

#### Track B — WebSearch

**In parallel with Track A**, make 2-4 targeted WebSearch calls covering different angles of the research topic:

- **Search 1**: Core topic (e.g., `"React vs Vue vs Svelte comparison 2026"`)
- **Search 2**: Practical angle (e.g., `"React vs Vue migration experience production"`)
- **Search 3** (if tech selection): Community/ecosystem (e.g., `"Vue ecosystem packages 2026"`)
- **Search 4** (if specific problem): Solution patterns (e.g., `"React state management best practices"`)

Derive search queries from the research topic — cover breadth, not just the obvious query.

### 4. Merge results

Combine findings from both tracks:

- **Both succeed**: Merge and cross-reference. Flag where Gemini and WebSearch agree (high confidence) vs diverge (needs Claude judgment).
- **Gemini fails, WebSearch succeeds**: Use WebSearch results as primary source. Note: "⚠️ Gemini unavailable — research based on WebSearch + Claude."
- **WebSearch fails, Gemini succeeds**: Use Gemini results. Note: "⚠️ WebSearch unavailable — research based on Gemini + Claude."
- **Both fail**: Claude researches from training data. Note: "⚠️ External search unavailable — research from Claude's training data only. Information may not reflect the latest developments."

**Never abort.** Always produce a report.

If the Bash tool was backgrounded or returned empty output, read the result from `~/.claude/logs/pi-gemini-last.out` (persisted by the script's `tee` safety net).

#### Failure diagnostics

When a track fails, include the specific reason in the status note:

**Gemini**: The script classifies errors in stderr (TIMEOUT, RATE_LIMIT, AUTH_ERROR, PERMISSION, NETWORK, CLI_ERROR, or CLI_NOT_FOUND). Include the classification and diagnostic message directly.

**WebSearch** (Claude tool — no stderr): If the tool returns an error or empty results, note "WebSearch returned no results for [query]." WebSearch failures are typically transient — note and continue.

### 5. Claude synthesis

Claude integrates all available research (Gemini + WebSearch + own knowledge):

- **Cross-check**: Do Gemini and WebSearch agree? Flag contradictions.
- **Supplement**: Add perspectives both tracks may have missed — especially version-sensitive or ecosystem-specific nuances.
- **Source attribution**: Attach URLs from WebSearch results and any URLs Gemini provided. Claims without a source URL are marked as (unverified).
- **Independent judgment**: Claude's own take on the topic, clearly labeled.

### 6. Integrated output

Structure the report:

```markdown
## Research: <topic>

### Provider Status
| Track | Status |
|-------|--------|
| Gemini | ✅ available / ⚠️ [reason] |
| WebSearch | ✅ available / ⚠️ [reason] |
| Claude | ✅ always available |

### Overview
[One-paragraph summary — synthesized from all tracks]

### [Main content sections — structure depends on topic]
[Comparison tables, recommendations, pitfalls, etc.]
[Label each section's source: Gemini / WebSearch / Claude / Consensus]

### Sources
| # | Source | URL |
|---|--------|-----|
| 1 | [description] | [url] |
```

### 7. Save results (optional)

After presenting the report, ask the user: **"Save the research results to a file?"**

If yes, save to `.claude/pi-research/<slug>.md` (slugify the topic, same convention as pi-plan). Include a metadata header:

```markdown
# Research: <topic>
- **Date**: <ISO 8601>
- **Providers**: <gemini + websearch + claude | gemini + claude | websearch + claude | claude-only>
- **Topic**: $ARGUMENTS
```

Create the directory if it doesn't exist.

### Notes

- Gemini call uses 90s timeout — same rationale as pi-fact-check (search grounding can be slow)
- WebSearch provides reliable URLs; Gemini provides deeper analysis but URLs may be hallucinated
- For fact-checking specific claims (not exploratory research), use `/pi-fact-check` instead
