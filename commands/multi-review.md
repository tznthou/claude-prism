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

### 4. Claude synthesis

After receiving both results, Claude performs integrated analysis:

#### 4.1 Consensus (both flagged)
Issues both Codex and Gemini identified — **high confidence, fix first**.

#### 4.2 Divergence (only one flagged)
Issues only one provider raised. Claude judges:
- Whether it's a real issue
- Why the other missed it (blind spot analysis)

#### 4.3 Claude's independent perspective
Issues neither provider caught but worth noting.

### 5. Output format

```
## 🔍 Multi-Provider Review Results

### 📊 Score Comparison
| Provider | Score | Focus Area |
|----------|-------|------------|
| Codex | X/10 | ... |
| Gemini | Y/10 | ... |
| Claude (Opus) | Z/10 | ... |

### ✅ Consensus Issues (high confidence, fix first)
...

### ⚡ Divergent Issues (needs judgment)
...

### 💡 Claude Supplements
...

### 📋 Action Items
1. ...
2. ...
```
