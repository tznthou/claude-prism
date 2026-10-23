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

Persist the full prompt (framing + project context) to a temp file, then call with the file on stdin (one invocation shape, no ARG_MAX exposure):

1. Bash: `PROMPT_FILE=$(mktemp -t prism-research-XXXXXX.md) && echo "$PROMPT_FILE"` — capture the path.
2. Use the Write tool to write the following prompt to that path (fill `$(date -u +%Y-%m-%d)` with today's date; append project context from Step 2 at the end if any):

```
You get exactly one turn: do not ask clarifying questions.
If the topic is underspecified, state your interpretation and proceed.
Work only from your search results: do not open web pages, fetch URLs, read files, or run commands.

Today is $(date -u +%Y-%m-%d). You are a technical researcher. Conduct in-depth research on the topic below. Search from multiple angles: the core topic, practical/production experience, and community sentiment — not just the obvious query.

Research topic: $ARGUMENTS

Provide:
1. Topic overview (one-paragraph summary)
2. The main approaches or schools of thought — as a pros/cons table if a comparison is natural for this topic
3. Recommended approach and reasoning
4. Common pitfalls and caveats
5. Recommended resources (official docs, tutorials, GitHub repos)
6. Source URLs for every key claim (one per line)

Anti-hallucination rules (strict):
- Only cite URLs that actually appeared in your search results — never construct, complete, or guess a URL.
- If a claim comes from your training data rather than your search results, mark it [KNOWLEDGE] — never present memory as a search finding.
- For version numbers, release dates, and breaking-change claims: quote the exact sentence as it appears in your search results, with its URL. If your search results contain no such sentence, mark the claim [LOW-CONFIDENCE] — do not open the page to find one.

If this involves tech selection, compare the leading options — typically 3, fewer if the field genuinely has fewer — across:
- Learning curve
- Community activity
- Performance
- Ecosystem
- Use cases

Dense over exhaustive — every claim should carry a source or a reason.

$(if project context exists)
Project context:
$PROJECT_CONTEXT
$(end if)
```

3. Call Gemini (Bash tool with timeout: 600000 — Bash tool's 10-minute ceiling, matches line 12 rule):

```bash
CLAUDE_PRISM_TIMEOUT=540 CLAUDE_PRISM_CALLER=pi-research ~/.claude/scripts/call-gemini.sh "technical research" < "$PROMPT_FILE"
```

#### Track B — WebSearch

**In parallel with Track A**, make 2-4 targeted WebSearch calls covering different angles of the research topic:

- **Search 1**: Core topic (e.g., `"React vs Vue vs Svelte comparison 2026"`)
- **Search 2**: Practical angle (e.g., `"React vs Vue migration experience production"`)
- **Search 3** (if tech selection): Community/ecosystem (e.g., `"Vue ecosystem packages 2026"`)
- **Search 4** (if specific problem): Solution patterns (e.g., `"React state management best practices"`)

Derive search queries from the research topic — cover breadth, not just the obvious query.

### 4. Merge results

Combine findings from both tracks:

- **Both succeed**: Merge and cross-reference. Flag where Gemini and WebSearch agree (high confidence) vs diverge (needs Claude judgment). **Divergence ruling**: official sources beat secondary commentary. For version numbers, breaking changes, or API-stability claims, Gemini grounding alone is not sufficient — cross-verify against an official source, else mark the claim (unverified). Gemini grounding has produced confident false alarms on such claims before.
- **Gemini fails, WebSearch succeeds**: Use WebSearch results as primary source. Note: "⚠️ Gemini unavailable — research based on WebSearch + Claude."
- **WebSearch fails, Gemini succeeds**: Use Gemini results. Note: "⚠️ WebSearch unavailable — research based on Gemini + Claude."
- **Both fail**: Claude researches from training data. Note: "⚠️ External search unavailable — research from Claude's training data only. Information may not reflect the latest developments."

**Never abort.** Always produce a report.

If the Bash tool was backgrounded or returned empty output, read the result from `~/.claude/logs/pi-gemini-last.out` (persisted by the script's `tee` safety net).

#### Failure diagnostics

When a track fails, include the specific reason in the status note:

**Gemini**: The script classifies errors in stderr (TIMEOUT, RATE_LIMIT, AUTH_ERROR, PERMISSION, NETWORK, EMPTY_OUTPUT, CLI_ERROR, or CLI_NOT_FOUND). Include the classification and diagnostic message directly.

**WebSearch** (Claude tool — no stderr): If the tool returns an error or empty results, note "WebSearch returned no results for [query]." WebSearch failures are typically transient — note and continue.

### 4.5 Source validation (Gemini-sourced URLs)

Sample Gemini-provided URLs for existence and content verification before synthesis. WebSearch URLs from recognized outlets can be trusted without verification.

**Resolve redirect links first.** Gemini usually cites through Google grounding redirect links (`https://vertexaisearch.cloud.google.com/grounding-api-redirect/…`), which hide the source's domain: until a link is resolved it can't be ranked, recognized as an official source, or matched against WebSearch's URLs. Create a temp file (`mktemp -t prism-research-urls-XXXXXX`, as in Step 3), write Gemini's redirect URLs into it with the Write tool (one per line), then resolve them in one Bash call — reading them from the file keeps model-written URLs off the shell command line:

```bash
while IFS= read -r u; do printf '%s\t%s\n' "$u" "$(curl -s -o /dev/null --max-time 10 -w '%{redirect_url}' "$u")"; done < "<URL_FILE>"
```

An empty target means the link no longer resolves: treat that source as `(unverified)`. From here on — sampling, synthesis, the Sources table — use the resolved URL, never the redirect.

**Sampling rules (cap: 5 URLs per run):**
- Priority 1: URLs backing the claims that feed the **Recommended approach** — these drive the report's conclusion
- Priority 2: URLs backing version numbers, release dates, or breaking-change claims
- Skip: URLs already marked [KNOWLEDGE] or [LOW-CONFIDENCE] by Gemini (already flagged), WebSearch-corroborated URLs

**For each sampled URL:** WebFetch it. WebFetch answers with a small model's reading of the page, not the page text, so ask what the page says about the claim's topic and have it quote the relevant sentences verbatim — leave Gemini's quote and claim out of the prompt (the reader tends to agree with whatever it is shown) — then compare those sentences with Gemini's quote yourself. A "not on the page" answer only means this reading missed it: the source becomes `(unverified)`, never evidence that the claim is false. Any failure (unreachable/4xx/5xx, content mismatch, quote not found, obviously fabricated) → mark the source `(unverified)`, do NOT use it as evidence, and note the reason.

If >50% of sampled URLs fail, mark **all** unsampled Gemini-sourced URLs `(unverified)` as well and note in the report: `⚠️ Gemini source validation: X/Y URLs failed — treat Gemini-only claims with caution.`

URLs not sampled (cap or low priority) appear with `(unverified)` in the Sources table.

### 5. Claude synthesis

Claude integrates all available research (Gemini + WebSearch + own knowledge):

- **Cross-check**: Do Gemini and WebSearch agree? Flag contradictions.
- **Supplement**: Add perspectives both tracks may have missed — especially version-sensitive or ecosystem-specific nuances.
- **Source attribution**: Attach URLs from WebSearch results and any URLs Gemini provided. Claims without a source URL are marked as (unverified).
- **Marker consumption**: Claims Gemini marked [KNOWLEDGE] or [LOW-CONFIDENCE] are treated as (unverified) unless WebSearch independently corroborates them.
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

- Gemini call uses `CLAUDE_PRISM_TIMEOUT=540` (heavy-class wrapper soft-timeout) inside the 600s Bash ceiling: a search-grounded answer took 319s on agy 1.4.6, past the old 300s. The wrapper returns as soon as Gemini does, so the ceiling only bounds a stalled call; the 60s buffer lets the wrapper's soft-timeout fire before the Bash ceiling
- WebSearch provides reliable URLs; Gemini provides deeper analysis but URLs may be hallucinated
- The Gemini prompt keeps Gemini on its search results: agy's headless print mode auto-denies any tool that needs approval (opening a page, reading a file, running a command), and a single denial empties the whole answer (EMPTY_OUTPUT)
