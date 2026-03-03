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

### 5. Present results

Show the review labeled **Codex**. If Codex makes obvious misjudgments (e.g., misunderstanding language features), Claude adds corrections.

### 6. Record review insights

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
  "source": "codex-only|claude-only|consensus"
}
```

Rules:
- Only record **actionable issues** (skip praise and generic comments)
- Map emoji severity to strings: 🔴→critical, 🟡→medium, 🟢→suggestion
- If Codex didn't give structured severity, infer from context
- Keep `title` under 80 chars
- Create the directory if it doesn't exist: `mkdir -p ~/.claude/logs`

### Notes

- Must be run inside a git repo (Codex CLI requirement)
- Codex output may include metadata (token counts etc.) — extract only the review content
