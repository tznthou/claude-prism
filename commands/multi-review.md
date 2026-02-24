---
command: multi-review
description: Triple-provider adversarial review — Codex + Gemini + Claude synthesis
---

# Multi-Provider Review (Codex + Gemini + Claude)

Send the same code to both Codex and Gemini for review, then Claude synthesizes and compares. **Three different AI perspectives, maximum blind spot elimination.**

## Execution

### 1. Determine review scope

Same as `/code-review`, based on `$ARGUMENTS`:
- No args → staged changes
- File path → specified file
- `--diff` → unstaged changes
- `--pr` → PR diff

### 2. Get the code

Use Bash / Read tool. **The same code goes to both providers.**

### 3. Call Codex + Gemini in parallel

Use **two parallel Bash tool calls**:

**Codex Review:**
```bash
~/.claude/scripts/call-codex.sh "You are a Senior Code Reviewer.
Focus: bugs, security vulnerabilities, performance, architecture issues.
Label each issue with severity (🔴/🟡/🟢) and line numbers.
End with an overall score (1-10).

Code:
$(code)"
```

**Gemini Review:**
```bash
~/.claude/scripts/call-gemini.sh "You are a Senior Code Reviewer.
Focus: design patterns, alternatives, maintainability, test coverage.
Label each issue with severity (🔴/🟡/🟢) and line numbers.
End with an overall score (1-10).

Code:
$(code)"
```

### 4. Handle partial failures (graceful degradation)

If one provider fails (script exits non-zero or returns an error message):
- **Do NOT abort the review.** Continue with the remaining providers.
- Claude always participates, so at minimum you have Claude + one external provider.
- In the output, clearly note which provider is absent and why (e.g., "Codex: unavailable — CLI not found").
- If **both** external providers fail, Claude performs a solo review and notes: "External providers unavailable — this is a single-perspective review."

### 5. Handle non-conforming output

External providers may not follow the requested format (no emoji severity, no 1-10 score, pure prose, etc.). When this happens:
- **Do NOT discard the response or force it into the template.** Extract actionable insights from the raw text.
- If a provider gave no numeric score, omit that cell from the Score Comparison table (use "—" instead) and note "score not provided by provider."
- For the Consensus/Divergence analysis, match issues by **semantic similarity** rather than format — the same bug described in different words still counts as consensus.

### 6. Claude synthesis

After receiving results (from however many providers succeeded), Claude performs integrated analysis:

#### 6.1 Consensus (multiple providers flagged)
Issues that two or more reviewers identified — **high confidence, fix first**.

#### 6.2 Divergence (only one flagged)
Issues only one provider raised. Claude judges:
- Whether it's a real issue
- Why the others missed it (blind spot analysis)

#### 6.3 Claude's independent perspective
Issues no other provider caught but worth noting.

### 7. Output format

```
## Multi-Provider Review Results

### Provider Status
| Provider | Status |
|----------|--------|
| Codex | [available/unavailable — reason] |
| Gemini | [available/unavailable — reason] |
| Claude | available (always) |

### Score Comparison
| Provider | Score | Focus Area |
|----------|-------|------------|
| Codex | X/10 or — | ... |
| Gemini | Y/10 or — | ... |
| Claude | Z/10 | ... |

### Consensus Issues (high confidence, fix first)
...

### Divergent Issues (needs judgment)
...

### Claude Supplements
...

### Action Items
1. ...
2. ...
```

### 8. Record review insights

**MUST do this as part of presenting results** — not as an optional follow-up.

After outputting the review, use the Bash tool to append a single-line JSON to the insights log:

```bash
echo '{"date":"<ISO 8601 UTC>","project":"<repo or directory name>","scope":"<staged|file:path|diff|pr>","providers":["<list of providers that responded>"],"issues":[<issue objects>]}' >> ~/.claude/logs/review-insights.jsonl
```

Each issue object in the `issues` array:
```json
{
  "category": "security|performance|design|logic|maintainability|accessibility|other",
  "severity": "critical|medium|suggestion",
  "title": "Brief one-line description of the issue",
  "source": "consensus|codex-only|gemini-only|claude-only"
}
```

Rules:
- Only record **actionable issues** (skip praise and generic comments)
- Map emoji severity to strings: 🔴→critical, 🟡→medium, 🟢→suggestion
- If a provider didn't give structured severity, infer from context (e.g., "security vulnerability" → critical)
- `source` reflects which providers flagged it: consensus (2+), or single-provider
- Keep `title` under 80 chars — enough to identify the pattern, not a full description
- Create the directory if it doesn't exist: `mkdir -p ~/.claude/logs`
