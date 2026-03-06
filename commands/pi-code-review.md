---
command: pi-code-review
description: Cross-provider code review via Codex — eliminate same-source blind spots
---

# Code Review via Codex

Use Codex CLI to review code. Core value: **the AI that wrote the code (Claude) is NOT the one reviewing it (Codex) — eliminates same-source blind spots**.

## Execution

### 1. Determine review scope

Based on `$ARGUMENTS`:
- **No args**: review `git diff --cached` (staged changes)
- **File path**: review the specified file
- **`--diff`**: review `git diff` (unstaged changes)
- **`--pr`**: review full PR diff (`git diff main...HEAD`)

### 1.5 Gather project guidelines

Search for project guideline files to use as compliance context:

```bash
# Check common locations for guideline files
for f in CLAUDE.md .claude/CLAUDE.md Agents.md .claude/Agents.md; do
  [ -f "$f" ] && echo "=== $f ===" && cat "$f"
done
```

- If **any** guideline files are found, their content becomes part of the review context (passed to the provider and used in confidence scoring).
- If **none** are found, skip this dimension — do not fabricate guidelines.
- Keep the raw guideline text available for Step 5 (confidence scoring).

### 2. Get the code

Use Bash tool to retrieve code content:
```bash
# staged changes (default)
git diff --cached

# specific file
cat <filepath>

# unstaged changes
git diff

# PR diff
git diff main...HEAD
```

### 3. Build prompt and call Codex

```bash
~/.claude/scripts/call-codex.sh "You are a Senior Code Reviewer. Review the following code.

Review focus:
1. Bugs and logic errors
2. Security vulnerabilities (OWASP Top 10)
3. Performance issues
4. Maintainability and code smells
5. Design patterns and architecture
6. Project guideline compliance (if guidelines provided below)

$(if guideline files were found)
Project Guidelines:
--- BEGIN GUIDELINES ---
$(guideline content from Step 1.5)
--- END GUIDELINES ---
Flag any violations of these guidelines as separate issues.
$(end if)

DO NOT flag:
- Pre-existing issues not introduced in this diff
- Issues that linters or formatters would catch (eslint, prettier, etc.)
- Pedantic nitpicks (naming style preferences without guideline backing)
- Lines with explicit lint-ignore / noqa / @ts-ignore comments
- General 'could be better' suggestions without concrete impact

Output format:
- Label each issue with severity: 🔴 Critical / 🟡 Medium / 🟢 Suggestion
- Include specific line numbers and fix suggestions
- End with an overall score (1-10)

Code:
$(code content)"
```

For long code (>3000 chars), use stdin mode:
```bash
echo "prompt + code" | ~/.claude/scripts/call-codex.sh "review"
```

### 4. Handle failures and non-conforming output

**If Codex fails** (script exits non-zero or CLI not found):
- Do NOT abort. Claude performs the review independently instead.
- Note in output: "Codex unavailable — Claude solo review (same-source blind spot caveat applies)."

**If Codex output doesn't match requested format** (no emoji severity, no score, pure prose):
- Extract actionable issues from the raw text. Do NOT discard the response.
- If no numeric score was given, omit the score or note "score not provided."

### 5. Confidence scoring & filtering

Before presenting, Claude scores **each** issue from Codex on a 0–100 confidence scale. **Only issues scoring ≥ 80 are shown.**

#### Scoring criteria (evidence-based, not opinion-based)

| Factor | Score Impact |
|--------|-------------|
| Issue references specific line numbers in the diff | +25 |
| Issue is about code **introduced in this diff** (not pre-existing) | +25 |
| Issue cites a concrete rule (OWASP, guideline, language spec) | +20 |
| Issue describes a reproducible scenario (steps, input, consequence) | +15 |
| Issue is about a pattern the diff **removes** or refactors away | −30 |
| Issue is something a linter/formatter would catch | −20 |
| Issue is a subjective style preference with no guideline backing | −20 |

Start each issue at 50 (neutral), apply factors, clamp to 0–100.

**Important**: The goal is to filter noise, **not** to let Claude override cross-provider findings based on its own opinion. If an issue has strong evidence (line numbers + concrete scenario) but Claude "disagrees", it still scores high and gets shown.

#### Guideline compliance issues

If project guidelines were found in Step 1.5, score guideline violations separately:
- Violation explicitly mentioned in guideline text → confidence +30
- Violation inferred but not explicitly stated → confidence +10
- Only show guideline violations that reference a **specific rule** from the guideline files.

### 5.5 Present results

Show the filtered review labeled **Codex**, grouped by confidence tier:
- **High confidence (≥ 90)**: Definitely fix
- **Solid (80–89)**: Worth fixing
- Issues below 80 are omitted. If the user wants to see them, they can re-run with `--verbose`.

If Codex makes obvious misjudgments (e.g., misunderstanding language features), Claude adds corrections. If project guidelines were found, add a **Guideline Compliance** section summarizing violations.

### 6. Record review insights

**MUST do this as part of presenting results** — not as an optional follow-up.

After outputting the review, use the Bash tool to append a single-line JSON to the insights log:

```bash
echo '{"date":"<ISO 8601 UTC>","project":"<repo or directory name>","scope":"<staged|file:path|diff|pr>","domain":"<frontend|backend|fullstack>","providers":["<list of providers that responded>"],"issues":[<issue objects>]}' >> ~/.claude/logs/review-insights.jsonl
```

Each issue object in the `issues` array:
```json
{
  "category": "security|performance|design|logic|maintainability|guideline|accessibility|other",
  "severity": "critical|medium|suggestion",
  "confidence": 80,
  "title": "Brief one-line description of the issue",
  "source": "codex-only|claude-only|consensus"
}
```

Rules:
- Only record issues that **passed the confidence filter** (≥ 80)
- Map emoji severity to strings: 🔴→critical, 🟡→medium, 🟢→suggestion
- If Codex didn't give structured severity, infer from context
- Use `"guideline"` category for project guideline violations
- Keep `title` under 80 chars
- Create the directory if it doesn't exist: `mkdir -p ~/.claude/logs`

### Notes

- Must be run inside a git repo (Codex CLI requirement)
- Codex output may include metadata (token counts etc.) — extract only the review content
