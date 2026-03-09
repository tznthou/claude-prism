---
command: pi-research
description: Technical research via Gemini — leverage Google's search integration
---

# Technical Research via Gemini

Use Gemini CLI for technical research. Gemini's strengths: broad ecosystem knowledge, alternative comparison, Google search integration.

## Execution

### 1. Understand the research topic

`$ARGUMENTS` is the research topic. If the topic is vague, clarify with AskUserQuestion:
- Research purpose (tech selection? learning? problem solving?)
- Depth needed (quick overview vs deep analysis)
- Constraints (tech stack, budget, team size)

### 2. Gather project context (if relevant)

If the research topic relates to the current project, use Read/Glob/Grep to collect relevant context (dependencies, existing patterns, config). Keep context under 4000 chars — summarize if needed.

### 3. Call Gemini

If project context was gathered, pipe it via stdin:
```bash
echo "$PROJECT_CONTEXT" | ~/.claude/scripts/call-gemini.sh "You are a technical researcher. Conduct in-depth research.

Research topic: $ARGUMENTS

Please provide:
1. Topic overview (one-paragraph summary)
2. Mainstream solution comparison (table format with pros/cons)
3. Recommended approach and reasoning
4. Common pitfalls and caveats
5. Recommended resources (official docs, tutorials, GitHub repos)

If this involves tech selection, compare at least 3 options across these dimensions:
- Learning curve
- Community activity
- Performance
- Ecosystem
- Use cases"
```

If no project context is needed:
```bash
~/.claude/scripts/call-gemini.sh "You are a technical researcher. Conduct in-depth research.

Research topic: $ARGUMENTS

(same prompt structure as above)"
```

### 4. Handle failures

If Gemini fails (script exits non-zero or CLI not found), Claude performs the research independently. Note in output: "Gemini unavailable — research conducted by Claude only (no Google search integration)."

### 5. Claude supplement

After Gemini responds, Claude adds:
- Perspectives Gemini may have missed
- Cross-checking claims that may be version-sensitive or ecosystem-specific (note any unverifiable claims rather than silently correcting)
- Claude's independent judgment on the topic

### 6. Integrated output

Merge Gemini research + Claude supplements into a structured report. Label each section's source (Gemini / Claude / Consensus).

### 7. Save results (optional)

After presenting the report, ask the user: **"Save the research results to a file?"**

If yes, save to `.claude/pi-research/<slug>.md` (slugify the topic, same convention as pi-plan). Include a metadata header:

```markdown
# Research: <topic>
- **Date**: <ISO 8601>
- **Providers**: <gemini, claude | claude-only>
- **Topic**: $ARGUMENTS
```

Create the directory if it doesn't exist.
