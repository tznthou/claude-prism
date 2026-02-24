---
command: ui-review
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

Output format:
- Label each issue with category and severity
- Include specific fix suggestions with code examples
- End with an overall UX score (1-10)

Code:
$(frontend code content)"
```

### 4. Screenshot analysis (if provided)

Skip Gemini CLI. Use Claude's Read tool to view the screenshot, then analyze with multimodal:
- Visual hierarchy and information architecture
- Color contrast and readability
- Typography and spacing
- Visibility of interactive elements

### 5. Present results

Label source: **Gemini** or **Claude (multimodal screenshot analysis)**.
