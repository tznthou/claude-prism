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
- **`--verbose`**: also show issues that were filtered out (< 80 confidence) with their scores

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
6. Inline annotation compliance — check if changes violate nearby code comments (IMPORTANT, WARNING, FIXME, TODO, NOTE annotations, or any comment that constrains how surrounding code should behave)
7. Project guideline compliance (if guidelines provided below)

Scope constraint: Focus on the diff provided. Do not speculate about code outside the diff unless directly referenced by the changed lines.

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
- Note in output: "Codex unavailable — review conducted by Claude only (same-source blind spot caveat applies)."

**If Codex output doesn't match requested format** (no emoji severity, no score, pure prose):
- Extract actionable issues from the raw text. Do NOT discard the response.
- If no numeric score was given, omit the score or note "score not provided."

### 5. Confidence scoring & filtering

Before presenting, Claude scores **each** issue from Codex using the [Confidence Scoring Framework](../spec/confidence-scoring-v1.md). **Only issues scoring ≥ 80 enter the output.**

#### 5.1 Evidence extraction

For each issue Codex raised, extract these fields:

1. **line_numbers** — Does the issue reference specific line numbers in the diff? (not vague "around line X")
2. **is_new_code** — Is the issue about code **introduced in this diff**? (not pre-existing code)
3. **rule_citation** — Does it cite a concrete rule (OWASP, language spec, project guideline, linter rule name)?
4. **has_reproduction** — Does it describe a reproducible scenario with steps, input, and expected vs actual outcome?
5. **references_removed_code_only** — Does it **solely** concern code the diff removes, with no impact on remaining code?
6. **is_linter_catchable** — Would a linter/formatter catch this? (only applies if the project has such tooling configured)
7. **is_subjective_style** — Is it a subjective style preference with no guideline backing? (distinguish from: readability backed by language idioms, maintainability with concrete impact, documented team conventions)
8. **references_exist_in_codebase** — Do all files, symbols, and APIs referenced in the issue actually exist? **Verify using Glob/Grep tools** — do not assume.

Each field is binary: applies or doesn't. When evidence is ambiguous, treat the factor as **not applicable**.

#### 5.2 Hallucination verification

If an issue references a specific file, function, class, or API:
- Use Glob/Grep to verify the reference exists in the codebase
- If any referenced symbol does not exist → mark `references_exist_in_codebase = false`
- This check is mandatory — hallucinated references are the strongest noise signal

#### 5.3 Score calculation

| Factor | Score Impact |
|--------|-------------|
| References specific line numbers in the diff | +25 |
| Code **introduced in this diff** (not pre-existing) | +25 |
| Cites a concrete rule (OWASP, guideline, language spec) | +20 |
| Describes a reproducible scenario (steps, input, consequence) | +15 |
| **Solely** concerns code the diff removes, with no impact on remaining code | −30 |
| Linter/formatter would catch it (and project has such tooling) | −25 |
| Subjective style preference with no guideline backing | −25 |
| References a file, symbol, or API that **does not exist** in the codebase | −50 |

```
score = clamp(40 + sum(applicable_factors), 0, 100)
```

**Critical rule**: Scoring must be **evidence-based**, not opinion-based. If an issue has strong evidence (line numbers + concrete scenario + cited rule) but Claude "disagrees" with the finding, it still scores high. The goal is noise filtering, not Claude vetoing cross-provider insights.

#### 5.4 Guideline compliance scoring

If project guidelines were found in Step 1.5, score guideline violations separately (no double-dip with "cites a rule" — use the higher bonus):
- Violation explicitly mentioned in guideline text → confidence +30 (replaces +20 rule citation if both apply)
- Violation inferred but not explicitly stated → confidence +10
- Only include violations that reference a **specific rule** from the guideline files.

### 5.5 Present results

Show the filtered review labeled **Codex**, grouped by confidence tier:
- **High confidence (≥ 90)**: Definitely fix
- **Solid (80–89)**: Worth fixing
- Issues below 80 are omitted by default.

#### GitHub suggestion blocks

When an issue has a **concrete code fix** (not just a description of the problem), include a GitHub suggestion block so the fix can be applied with one click in a PR:

````
**`src/utils/auth.ts:42`** 🔴 SQL injection via unsanitized input

```suggestion
const result = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
```
````

Rules:
- Only use suggestion blocks when the replacement code is **unambiguous** — if there are multiple valid fixes, describe the options in prose instead.
- Include the **file path and line number** as a bold header before the block.
- The content inside ` ```suggestion ``` ` must be the **exact replacement** for the referenced line(s) — no surrounding context, no line numbers, no diff markers.
- When reviewing a diff (`--diff`, `--pr`), match the line numbers to the **new file** side of the diff.
- If the fix spans multiple lines, include all lines in a single suggestion block.
- Issues without a concrete fix (e.g., architectural concerns, design questions) should remain as prose descriptions — do NOT force a suggestion block.

If `--verbose` was specified, add a **Filtered Issues** section after the main results:
```
### Filtered Issues (< 80 confidence)
| # | Issue | Score | Reason filtered |
|---|-------|-------|-----------------|
| 1 | Brief description | 65 | subjective style (-25) |
| 2 | Brief description | 40 | no line numbers, no evidence |
```

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
