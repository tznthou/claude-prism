---
command: research
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

### 2. Call Gemini

```bash
~/.claude/scripts/call-gemini.sh "You are a technical researcher. Conduct in-depth research.

Research topic: $ARGUMENTS

Please provide:
1. 📋 Topic overview (one-paragraph summary)
2. 🔍 Mainstream solution comparison (table format with pros/cons)
3. 🏗️ Recommended approach and reasoning
4. ⚠️ Common pitfalls and caveats
5. 📚 Recommended resources (official docs, tutorials, GitHub repos)

If this involves tech selection, compare at least 3 options across these dimensions:
- Learning curve
- Community activity
- Performance
- Ecosystem
- Use cases"
```

### 3. Handle failures

If Gemini fails (script exits non-zero or CLI not found), Claude performs the research independently. Note in output: "Gemini unavailable — research conducted by Claude only (no Google search integration)."

### 4. Claude supplement

After Gemini responds, Claude adds:
- Perspectives Gemini may have missed
- Corrections for potentially outdated information
- Claude's independent judgment on the topic

### 5. Integrated output

Merge Gemini research + Claude supplements into a structured report. Label each section's source (Gemini / Claude / Consensus).
