# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## v0.9.9 (2026-03-15)

**New Command & Trigger Refinement**

- **New `/pi-askall` command** — ask Codex and Gemini the same question in parallel, then Claude synthesizes all three perspectives. Works with any topic (code, architecture, strategy, writing, decisions) — not limited to code review
- **Narrowed `/pi-plan` trigger scope** — now triggers only for architectural decisions, tech stack selection, and tasks with multiple viable approaches. Simple task breakdown is left to Claude Code's built-in plan mode

## v0.9.8 (2026-03-12)

**Review Quality Improvements** — three new review dimensions inspired by analysis of Anthropic's official code-review plugin.

- **Historical PR comments** — review commands and `ci-review.sh` now query review comments from recent merged PRs that touched the same files, surfacing recurring issues as high-confidence context. CI uses a single GraphQL query; slash commands use `gh` CLI interactively
- **Inline annotation compliance** — all review commands now check if changes violate nearby code comments (`IMPORTANT`, `WARNING`, `FIXME`, `TODO`, `NOTE` annotations)
- **Diff scope constraint** — provider prompts now explicitly constrain reviewers to focus on the diff, reducing hallucination and out-of-scope noise
- **Removed `/pi-exec`** — Claude Code is already a powerful agentic executor with built-in task tracking (TodoWrite) and cross-session resume (RESUME.md). `/pi-exec` duplicated these native capabilities without adding cross-provider value
- **Repositioned core narrative** — added "Why claude-prism?" comparison table contrasting cross-provider review with single-provider multi-agent approaches
- **Diff hunk validation for inline suggestions** — `ci-review.sh` now validates that suggestion line numbers fall within actual diff hunks before posting via the GitHub Reviews API

## v0.9.7 (2026-03-09)

**GitHub Suggestion Blocks** — review commands now output one-click fixable code suggestions.

- **Suggestion block output** — `/pi-code-review`, `/pi-multi-review`, `/pi-ui-review` now include GitHub `suggestion` blocks for issues with concrete, unambiguous code fixes
- **Inline PR review comments** — `ci-review.sh` parses suggestion blocks and posts them as inline review comments via the GitHub Reviews API, enabling one-click "Apply suggestion" in PRs
- **Graceful fallback** — if the Reviews API fails or no suggestions are found, falls back to regular PR comment (fully backward-compatible)

## v0.9.6 (2026-03-09)

**Prompt Quality & Consistency** — multi-provider review of all 9 command prompts, with fixes.

- **Confidence scoring implemented** — evidence extraction, hallucination verification, and `--verbose` flag applied to all 3 review commands (`/pi-code-review`, `/pi-multi-review`, `/pi-ui-review`), aligned with [spec v1.0](spec/confidence-scoring-v1.md)
- **Fix: pi-exec resume bug** — plan step checkbox syntax (`1. [ ]` vs `- [ ]`) mismatch between `/pi-plan` and `/pi-exec` caused resume detection to fail
- **Fix: pi-ask-gemini "review" prefix** — code context invocation hardcoded `"review"` as the prompt, biasing Gemini's response
- **Standardized stdin pipe invocation** — all commands with code context now use `echo "context" | call-xxx.sh "$ARGUMENTS"` pattern consistently (avoids ARG_MAX limits)
- **`/pi-research` enhanced** — added project context awareness, optional save-to-file (`.claude/pi-research/`), and improved Claude supplement wording
- **`/pi-ui-design` fixed** — resolved undefined variables (`$DESIGN_SPEC_CONTENT`, `$USER_INPUT`), standardized to `$ARGUMENTS` and stdin pipe
- **Context budget** — all commands with code/context injection now enforce a 4000 char limit with summarization guidance
- **Internationalization** — removed hardcoded Chinese text from command prompts; output language now follows user's own Claude Code language settings
- **Failure message consistency** — standardized format across all commands: `"[Provider] unavailable — [action] by Claude only."`

## v0.9.5 (2026-03-09)

**Supply Chain Security** — improve [socket.dev](https://socket.dev) score and npm packaging.

- **npm `files` precision** — excluded CI-only scripts (`ci-review.sh`, `review-insights.sh`, `usage-summary.sh`) from npm package; only runtime scripts shipped
- **`bugs` field** — added `bugs.url` to `package.json` for npm metadata completeness
- **npm OIDC Trusted Publishing** — CI uses Node 24 + OIDC for npm publish with provenance (no `NPM_TOKEN` secret needed)

## v0.9.1 (2026-03-06)

**Security & Bug Fixes** — audit-driven hardening across all scripts.

- **Prompt injection defense** — `ci-review.sh` now wraps both GUIDELINES and DIFF blocks with explicit data boundary markers to prevent LLM instruction injection
- **stderr/stdout separation** — `call-gemini.sh` and `call-codex.sh` no longer mix stderr into AI responses; errors are logged and forwarded to stderr separately
- **`gh` CLI dependency check** — `ci-review.sh --pr` mode now validates `gh` availability before attempting to fetch PR diff
- **`--sandbox` whitelist** — `call-codex.sh` validates sandbox mode against allowed values (`read-only`, `sandbox`, `none`)
- **`review-insights.sh` rewrite** — switched from fragile sed/grep JSON parsing to `jq`; added `jq` dependency check; fixed unquoted variable references
- **Schema consistency** — `pi-code-review.md` logging schema now includes `domain` field (matching `pi-multi-review.md`)
- **Domain detection tests** — 6 new test cases for `detect-domain.sh` (smoke test: 26 → 32)
- **Docs** — added CLI version compatibility table and checksums trust model explanation to README

## v0.9.0 (2026-03-05)

**Confidence Scoring & Guideline Compliance** — evidence-based noise filtering and project rule enforcement across all review commands.

- **Confidence scoring** — every review issue scored 0–100 on evidence quality (line numbers, cited rules, reproducibility, consensus). Only issues ≥ 80 shown. Scoring is evidence-based, not opinion-based — Claude cannot veto cross-provider findings with strong evidence
- **Guideline compliance** — auto-discovers `CLAUDE.md` and `Agents.md` in the project, checks code against project-specific rules. Ready for the emerging `Agents.md` standard
- **False positive filtering** — explicit exclusion rules in all review prompts: no pre-existing issues, no linter-detectable problems, no pedantic nitpicks, no lint-ignore lines
- **Applied to**: `/pi-code-review`, `/pi-multi-review`, `/pi-ui-review`, `ci-review.sh`
- **Review insights enhanced** — JSON schema adds `confidence` score and `guideline` category

## v0.8.0 (2026-03-04)

**Distribution** — added `npx` and Homebrew install support.

- `npx claud-prism-aireview` for one-command install
- `brew tap tznthou/claude-prism && brew install claud-prism-aireview` for macOS
- Added GitHub Release workflow for automated npm publishing
- Legacy command cleanup in install/uninstall scripts

## v0.7.0 (2026-03-04)

**Smart Routing, Plan/Execute & Command Namespace** — domain-aware review weighting, persistent planning, and `pi-` prefix for all commands.

### Breaking: `pi-` command prefix

All 9 commands are now prefixed with `pi-` (e.g., `/code-review` → `/pi-code-review`, `/research` → `/pi-research`).

**Why?** Claude Code has a built-in `/plan` command (enters plan mode). Our new `/plan` command for persistent planning would collide with it. Rather than only prefixing the conflicting commands, we chose to prefix **all** commands uniformly for namespace safety and brand identity. The `pi-` prefix (from **P**rism **I**nitial) is short enough to type quickly while making it clear which commands belong to claude-prism.

**Migration:** After updating, re-run `./install.sh`. The installer will overwrite the old command files. To clean up old (unprefixed) commands manually:

```bash
cd ~/.claude/commands
rm -f ask-codex.md ask-gemini.md code-review.md multi-review.md \
     research.md ui-design.md ui-review.md plan.md execute.md
```

### Smart routing

`/pi-multi-review` now auto-detects the **domain** of the code changes (frontend / backend / fullstack) and adjusts provider weight during synthesis.

**How it works:**

1. File paths from the review scope are piped to `detect-domain.sh`
2. The script classifies each file by extension and path:
   - Frontend signals: `.css`, `.tsx`, `.jsx`, `.vue`, `.svelte`, `.html`, `.svg` / `components/`, `pages/`, `styles/`, `ui/`
   - Backend signals: `.go`, `.py`, `.rs`, `.java`, `.sql`, `.proto` / `api/`, `controllers/`, `models/`, `middleware/`, `migrations/`
   - Neutral (not counted): `.ts`, `.js`, `.json`, `.yaml`, `.md`, `.sh`
3. If ≥ 70% of classifiable files lean one way → that domain; otherwise → `fullstack`

**During synthesis:**

| Domain | Gemini weight | Codex weight | Rationale |
|--------|-------------|------------|-----------|
| frontend | Higher | Standard | Gemini excels at UI/UX, accessibility, design patterns |
| backend | Standard | Higher | Codex excels at algorithms, security, API design |
| fullstack | Equal | Equal | No domain advantage |

**Design philosophy: "weight, don't route."** Both providers are **always** called. The domain only affects how Claude resolves disagreements — if both providers agree on an issue, it's reported regardless of weighting. This preserves graceful degradation: if one provider is down, the other still covers the full review.

### Plan/Execute

Two new commands for persistent, cross-session task planning:

**`/pi-plan <task description>`** — Analyze the codebase and generate a structured plan file:

- Optionally consults Codex and Gemini in parallel for independent technical analysis
- Detects domain via `detect-domain.sh` to contextualize recommendations
- Outputs a markdown plan to `.claude/pi-plans/<slug>.md` with: context, multi-provider analysis, step-by-step implementation (with checkboxes), key files, risks, and verification criteria
- **Does not auto-execute** — the plan is a proposal for the user to review

**`/pi-exec <plan-file>`** — Execute a plan step by step:

- Reads the plan, validates status (draft / approved / in-progress / completed)
- Executes each step sequentially, updating `- [ ]` → `- [x]` as it goes
- If a step fails, stops and asks the user how to proceed
- **Resume support:** If a session ends mid-execution, running `/pi-exec` on the same file resumes from the first unchecked step — no progress is lost

**Why not SESSION_ID?** Some planning tools use session IDs and a separate binary to track state. We use markdown checkboxes instead — the plan file itself **is** the state. This keeps the mechanism simple (no external dependencies), human-readable (you can edit the plan in any editor), and consistent with our zero-compile-dependency principle.

### Other changes

- **Review insights enhanced** — `review-insights.jsonl` now includes a `domain` field for domain-aware trend analysis
- **`detect-domain.sh`** — new standalone utility script (can be used outside of multi-review; reads file paths from stdin)

## v0.6.0 (2026-03-03)

**Security Hardening** — security audit and fixes across all shell scripts:

- **Temp file safety** — `review-insights.sh` now uses `mktemp` instead of a predictable `/tmp` path (symlink attack prevention)
- **Input validation** — `ci-review.sh` validates `--pr` argument as a positive integer
- **Process visibility** — `call-codex.sh` and `call-gemini.sh` now always pipe prompts via stdin (prevents exposure in `ps` output)
- **Install integrity** — `install.sh` verifies SHA256 checksums before installing (new `checksums.sha256` file)
- **ShellCheck CI** — new GitHub Actions workflow for static analysis on all shell scripts
- **ShellCheck fixes** — removed unused variables, fixed invalid `>=` operator, quoted command substitutions

## v0.5.0 (2026-02-24)

**CI/CD Integration** — automated multi-provider PR review via GitHub Actions:

- **`ci-review.sh`** — CI/CD review orchestrator that calls Gemini API + OpenAI API in parallel, with optional Claude synthesis. Uses REST APIs directly (no CLI installation needed)
- **GitHub Actions workflow** (`ai-review.yml`) — label-triggered or auto-triggered PR review with concurrency control
- **Graceful degradation in CI** — works with any combination of API keys (1-3 providers)
- **Large diff handling** — auto-truncation at 32K chars (configurable via `MAX_DIFF_CHARS`)
- Smoke test expanded to 24 tests (from 20)

## v0.4.0 (2026-02-24)

**Reliability & Observability** — graceful degradation, usage tracking, and review insights:

- **Graceful degradation** across all 7 commands — if a provider fails, Claude continues with remaining providers instead of aborting. Non-conforming output (no emoji, no score) is handled via semantic extraction
- **`usage-summary.sh`** — per-provider call stats, success/error breakdown, estimated token consumption (`--week`, `--all`, `--date`)
- **`review-insights.sh`** — analyze recurring patterns from review history (category/severity distribution, consensus vs. single-provider findings, most frequent issues)
- **Review insights auto-recording** — `/code-review` and `/multi-review` append structured JSONL after each review for trend analysis
- Smoke test expanded to 20 tests (from 14)

## v0.3.1 (2026-02-24)

- **`/ui-design` redesigned** — now generates a previewable HTML mockup (Tailwind CDN) from design spec files
- Workflow: design spec → HTML mockup → browser preview → confirm → Claude Code implements
- Text input (no spec file) triggers a two-step flow: generate spec → generate mockup
- Next steps presented as choices (adjust, implement, or `/ui-review`)

## v0.3.0 (2026-02-24)

- New command: `/ui-design` — UI/UX design spec generation via Gemini (information architecture, wireframes, component breakdown, visual direction)
- Optional `--html` flag generates a self-contained HTML prototype with Tailwind CDN
- Auto-detects project tech stack to inform design suggestions

## v0.2.1 (2026-02-24)

**Script hardening** — fixes identified via `/multi-review` (Codex + Gemini + Claude triple-provider review):

- **`-m` flag guard**: `-m` without a value now shows a clear error instead of crashing with "unbound variable" (`set -u`)
- **Deduplicate execution logic**: merged identical error handling from the if/else branches into a single `|| { ... }` block
- **Sanitize error logs**: error log entries no longer include response content (which could contain source code or tokens); only exit code is logged

## v0.2.0 (2026-02-24)

- Initial public release
- 6 slash commands: `/ask-codex`, `/ask-gemini`, `/code-review`, `/ui-review`, `/research`, `/multi-review`
- Model defaults deferred to CLI built-in (no hardcoded versions)
- Dry-run exits before binary check (works without CLI installed)
