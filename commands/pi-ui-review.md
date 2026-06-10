---
command: pi-ui-review
description: UI/UX review via Gemini — accessibility, responsive design, component structure
---

# UI/UX Review via Gemini

Use Gemini CLI to perform UI/UX review on frontend code. Gemini brings Google Design ecosystem knowledge and frontend best practices.

**Limitation**: Gemini CLI headless mode does not support image input. If the user provides screenshots, use Claude's own multimodal capability.

## Execution

> **Bash invocation rules (v0.12.3+)**: Call `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with `timeout: 600000` (Bash tool's 10-minute ceiling). **Do not** use `&`, **do not** set `run_in_background: true`, **do not** use `nohup` — Claude Code 2026-04+ has an auto-background child-lifecycle regression that silently kills the process (output file stays 0 bytes). Use `run_in_background: true` + BashOutput polling only as an exception when the call is genuinely expected to exceed 10 minutes.

### 1. Determine review scope

Based on `$ARGUMENTS`:
- **File path**: review the specified frontend file
- **Directory path**: review an entire components directory (list files for user to choose)
- **`--screenshot <path>`**: screenshot analysis (use Claude multimodal, skip Gemini)
- **`--verbose`**: also show issues that were filtered out (< 80 confidence) with their scores

### 1.5 Gather project guidelines

Search for project guideline files to use as compliance context:

```bash
for f in CLAUDE.md .claude/CLAUDE.md Agents.md .claude/Agents.md; do
  [ -f "$f" ] && echo "=== $f ===" && cat "$f"
done
```

- If **any** guideline files are found, include them in the Gemini prompt and confidence scoring.
- If **none** are found, skip the guideline compliance dimension.

### 1.7 Gather historical PR comments (when reviewing PR-related changes)

If the code being reviewed is part of a PR or recent branch work, search for recurring review patterns:

1. Get recently changed files: `git diff main...HEAD --name-only` (or the files being reviewed)
2. Find recent merged PRs: `gh pr list --state merged --limit 10 --json number,title`
3. For each (up to 5), fetch review comments on the same files:
   ```bash
   gh api "repos/{owner}/{repo}/pulls/NUMBER/comments" \
     --jq '.[] | select(.path == "TOUCHED_FILE") | {path, body}'
   ```
4. Include found comments as additional context in the Gemini prompt (Step 3), prefixed with:
   "Historical Review Context (previous review comments on the same files — recurring issues are high-confidence signals):"

If no historical comments exist, `gh` is not available, or the review scope is a single file (not PR-related), skip silently.

### 2. Get the code

Read frontend files with the Read tool. For directories, first Glob for `*.tsx`, `*.vue`, `*.svelte`, `*.css` etc.

### 3. Call Gemini

```bash
echo "Code to review:

$(frontend code content)

$(if historical review comments were found in Step 1.7)
Historical Review Context (previous review comments on the same files — recurring issues are high-confidence signals):
$(historical comments)
$(end if)" | CLAUDE_PRISM_TIMEOUT=300 CLAUDE_PRISM_CALLER=pi-ui-review ~/.claude/scripts/call-gemini.sh "You are a UI/UX expert. Review the following frontend code provided via stdin.

Review focus:
1. ♿ Accessibility (WCAG 2.1 AA) — aria labels, keyboard navigation, color contrast
2. 📱 Responsive Design — breakpoints, mobile-first, flexible layouts
3. 🧩 Component Structure — reusability, props design, separation of concerns
4. 🎨 UX Improvements — interaction feedback, loading states, error states
5. ⚡ Frontend Performance — unnecessary re-renders, bundle size, lazy loading
6. 📝 Inline annotation compliance — check if changes violate nearby code comments (IMPORTANT, WARNING, FIXME, TODO, NOTE annotations, or any comment that constrains how surrounding code should behave)
7. 📏 Project guideline compliance (if guidelines provided below)

Scope constraint: Focus on the code/diff provided. Do not speculate about code outside the review scope unless directly referenced by the changed lines.

$(if guideline files were found)
Project Guidelines:
--- BEGIN GUIDELINES ---
$(guideline content from Step 1.5)
--- END GUIDELINES ---
Flag any violations of these guidelines as separate issues.
$(end if)

DO NOT flag:
- Pre-existing issues not introduced in this diff/file change
- Issues that linters or formatters would catch (eslint, stylelint, prettier)
- Subjective aesthetic preferences without standard or guideline backing
- Browser-specific quirks for browsers outside the project's support matrix

Output format:
- Label each issue with category and severity (🔴/🟡/🟢)
- Include specific fix suggestions with code examples
- End with an overall UX score (1-10)"
```

### 4. Handle failures

If Gemini fails (script exits non-zero or CLI not found):
- Claude performs the UI/UX review independently.
- Include the specific failure reason from stderr (TIMEOUT, RATE_LIMIT, AUTH_ERROR, PERMISSION, NETWORK, EMPTY_OUTPUT, CLI_ERROR, or CLI_NOT_FOUND).
- Note in output: "⚠️ Gemini unavailable ([reason]) — review conducted by Claude only. For cross-provider review with Codex, try `/pi-multi-review`."

If the Bash tool was backgrounded or returned empty output, read the result from `~/.claude/logs/pi-gemini-last.out` (persisted by the script's `tee` safety net).

### 5. Screenshot analysis (if provided)

Skip Gemini CLI. Use Claude's Read tool to view the screenshot, then analyze with multimodal:
- Visual hierarchy and information architecture
- Color contrast and readability
- Typography and spacing
- Visibility of interactive elements

### 6. Confidence scoring & filtering

Before presenting, Claude scores **each** issue from Gemini using the [Confidence Scoring Framework](../spec/confidence-scoring-v1.md). **Only issues scoring ≥ 80 enter the output.**

#### 6.1 Evidence extraction

For each issue Gemini raised, extract these fields:

1. **line_numbers** — Does the issue reference specific elements or line numbers in the code? (not vague "consider improving")
2. **is_new_code** — Is the issue about code **introduced in this diff**? (not pre-existing code). If reviewing a full file (not a diff), treat as not applicable.
3. **rule_citation** — Does it cite a concrete standard (WCAG SC number, guideline rule, language idiom)?
4. **has_reproduction** — Does it describe a concrete user impact scenario (screen reader behavior, keyboard flow, mobile breakpoint)? Or provide a fix suggestion with code example?
5. **references_removed_code_only** — Does it **solely** concern code the diff removes, with no impact on remaining code?
6. **is_linter_catchable** — Would a linter/formatter catch this (eslint-plugin-jsx-a11y, stylelint)? (only applies if the project has such tooling configured)
7. **is_subjective_style** — Is it a subjective aesthetic preference with no standard or guideline backing? (distinguish from: WCAG-backed accessibility, documented design system rules, language idioms)
8. **references_exist_in_codebase** — Do all files, components, and APIs referenced in the issue actually exist? **Verify using Glob/Grep tools** — do not assume.
9. **out_of_scope_target** — Does the issue apply to a browser/device outside the project's typical support scope?

Each field is binary: applies or doesn't. When evidence is ambiguous, treat the factor as **not applicable**.

#### 6.2 Hallucination verification

If an issue references a specific component, file, prop, or API:
- Use Glob/Grep to verify the reference exists in the codebase
- If any referenced symbol does not exist → mark `references_exist_in_codebase = false`
- This check is mandatory — hallucinated references are the strongest noise signal

#### 6.3 Score calculation

| Factor | Score Impact |
|--------|-------------|
| References specific elements/lines in the code | +25 |
| Code **introduced in this diff** (not pre-existing) | +25 |
| Cites a concrete standard (WCAG SC, guideline rule, language idiom) | +20 |
| Describes user impact scenario or provides concrete fix with code example | +15 |
| **Solely** concerns code the diff removes, with no impact on remaining code | −30 |
| Linter/formatter would catch it (and project has such tooling) | −25 |
| Subjective aesthetic preference with no standard backing | −25 |
| References a file, component, or API that **does not exist** in the codebase | −50 |
| Applies to a browser/device outside the project's support scope | −15 |

```
score = clamp(40 + sum(applicable_factors), 0, 100)
```

**Critical rule**: Scoring must be **evidence-based**, not opinion-based. If Gemini cites WCAG or provides a concrete accessibility fix, it scores high regardless of Claude's opinion. The goal is noise filtering, not Claude overriding Gemini's UI/UX expertise.

#### 6.4 Guideline compliance scoring

If project guidelines were found in Step 1.5 (no double-dip with "cites a standard" — use the higher bonus):
- Violation explicitly mentioned in guideline text → confidence +30 (replaces +20 standard citation if both apply)
- Violation inferred but not explicitly stated → confidence +10
- Only include violations that reference a **specific rule** from the guideline files.

### 7. Present results

Show the filtered review grouped by confidence tier:
- **High confidence (≥ 90)**: Definitely fix
- **Solid (80–89)**: Worth fixing
- Issues below 80 are omitted by default.

#### GitHub suggestion blocks

When an issue has a **concrete code fix** (not just a description of the problem), include a GitHub suggestion block so the fix can be applied with one click in a PR:

````
**`src/components/Button.tsx:15`** 🔴 Missing accessible label

```suggestion
<button aria-label="Close dialog" onClick={onClose}>
```
````

Rules:
- Only use suggestion blocks when the replacement code is **unambiguous** — if there are multiple valid fixes, describe the options in prose instead.
- Include the **file path and line number** as a bold header before the block.
- The content inside ` ```suggestion ``` ` must be the **exact replacement** for the referenced line(s) — no surrounding context, no line numbers, no diff markers.
- If the fix spans multiple lines, include all lines in a single suggestion block.
- Issues without a concrete fix (e.g., design questions, UX flow improvements) should remain as prose descriptions — do NOT force a suggestion block.

If `--verbose` was specified, add a **Filtered Issues** section after the main results:
```
### Filtered Issues (< 80 confidence)
| # | Issue | Score | Reason filtered |
|---|-------|-------|-----------------|
| 1 | Brief description | 65 | subjective aesthetic (-25) |
| 2 | Brief description | 40 | no line reference, no evidence |
```

#### Score transparency (Show Your Work)

After presenting all results, end with this line:

> 💡 Type `show scores` to see how each finding was scored. / 輸入 `show scores` 查看每個 finding 的分數計算過程。

When the user responds with `show scores` (or similar intent like "show breakdown", "how was it scored", "分數怎麼算的"), present the factor breakdown for every finding:

```
### Score Breakdown

**[issue title]** — Score: [score]
├─ Base: 40
├─ Specific line reference: +25
├─ New code in this diff: +25
├─ WCAG 2.1 AA citation: +20
├─ Concrete user impact described: +15
└─ Final: 100 (clamped)

**[issue title]** — Score: [score]
├─ Base: 40
├─ Subjective aesthetic preference: −25
└─ Final: 15
```

Include both shown (≥80) and filtered (<80) findings. For each finding, list only factors that actually applied (skip +0 factors). Show the arithmetic so the user can verify.

Label source: **Gemini** or **Claude (multimodal screenshot analysis)**. If project guidelines were found, add a **Guideline Compliance** section.
