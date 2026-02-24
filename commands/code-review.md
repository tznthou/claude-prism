---
command: code-review
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

### 4. Present results

Show the review labeled **Codex**. If Codex makes obvious misjudgments (e.g., misunderstanding language features), Claude adds corrections.

### Notes

- Must be run inside a git repo
- Codex output may include metadata (token counts etc.) — extract only the review content
