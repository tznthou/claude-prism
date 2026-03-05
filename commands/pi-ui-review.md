---
command: pi-ui-review
description: UI/UX review via Gemini — accessibility, responsive design, component structure
---

# UI/UX Review via Gemini

Use Gemini CLI to perform UI/UX review on frontend code. Gemini brings Google Design ecosystem knowledge and frontend best practices.

**Limitation**: Gemini CLI headless mode does not support image input. If the user provides screenshots, use Claude's own multimodal capability.

## Execution

### 1. Determine review scope

Based on `$ARGUMENTS`:
- **File path**: review the specified frontend file
- **Directory path**: review an entire components directory (list files for user to choose)
- **`--screenshot <path>`**: screenshot analysis (use Claude multimodal, skip Gemini)

### 1.5 Gather project guidelines

Search for project guideline files to use as compliance context:

```bash
for f in CLAUDE.md .claude/CLAUDE.md Agents.md .claude/Agents.md; do
  [ -f "$f" ] && echo "=== $f ===" && cat "$f"
done
```

- If **any** guideline files are found, include them in the Gemini prompt and confidence scoring.
- If **none** are found, skip the guideline compliance dimension.

### 2. Get the code

Read frontend files with the Read tool. For directories, first Glob for `*.tsx`, `*.vue`, `*.svelte`, `*.css` etc.

### 3. Call Gemini

```bash
~/.claude/scripts/call-gemini.sh "You are a UI/UX expert. Review the following frontend code.

Review focus:
1. ♿ Accessibility (WCAG 2.1 AA) — aria labels, keyboard navigation, color contrast
2. 📱 Responsive Design — breakpoints, mobile-first, flexible layouts
3. 🧩 Component Structure — reusability, props design, separation of concerns
4. 🎨 UX Improvements — interaction feedback, loading states, error states
5. ⚡ Frontend Performance — unnecessary re-renders, bundle size, lazy loading
6. 📏 Project guideline compliance (if guidelines provided below)

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
- End with an overall UX score (1-10)

Code:
$(frontend code content)"
```

### 4. Handle failures

If Gemini fails (script exits non-zero or CLI not found), Claude performs the UI/UX review independently. Note in output: "Gemini unavailable — review conducted by Claude only."

### 5. Screenshot analysis (if provided)

Skip Gemini CLI. Use Claude's Read tool to view the screenshot, then analyze with multimodal:
- Visual hierarchy and information architecture
- Color contrast and readability
- Typography and spacing
- Visibility of interactive elements

### 6. Confidence scoring & filtering

Before presenting, Claude scores **each** issue from Gemini on a 0–100 confidence scale. **Only issues scoring ≥ 80 are shown.**

#### Scoring criteria (evidence-based, not opinion-based)

| Factor | Score Impact |
|--------|-------------|
| Issue cites a specific standard (WCAG SC, guideline rule) | +25 |
| Issue references specific elements/lines in the code | +25 |
| Issue has a concrete fix suggestion with code example | +15 |
| Issue describes user impact (screen reader, keyboard, mobile) | +15 |
| Issue is a subjective aesthetic preference with no standard backing | −25 |
| Issue is about a linter/formatter-detectable problem | −20 |
| Issue applies to a browser/device outside typical support scope | −15 |

Start each issue at 50 (neutral), apply factors, clamp to 0–100.

**Important**: The goal is to filter noise, **not** to let Claude override Gemini's UI/UX expertise. If Gemini cites WCAG or provides a concrete accessibility fix, it scores high regardless of Claude's opinion.

#### Guideline compliance issues

If project guidelines were found in Step 1.5:
- Violation explicitly mentioned in guideline text → confidence +30
- Violation inferred but not explicitly stated → confidence +10

### 7. Present results

Show the filtered review grouped by confidence tier:
- **High confidence (≥ 90)**: Definitely fix
- **Solid (80–89)**: Worth fixing
- Issues below 80 are omitted. Re-run with `--verbose` to see them.

Label source: **Gemini** or **Claude (multimodal screenshot analysis)**. If project guidelines were found, add a **Guideline Compliance** section.
