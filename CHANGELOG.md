# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## v0.11.0 (2026-03-27)

**Provider Resilience** — dual-track research, structured error diagnostics, and graceful degradation across all commands.

Driven by Gemini CLI service degradation (Discussion [#22970](https://github.com/google-gemini/gemini-cli/discussions/22970): paid users hitting 429 errors, 7–10 min latency, 24hr+ outages post-March 25 update), this release hardens every command against provider instability.

### Dual-track research

- **`/pi-research` upgraded to dual-track** — now launches Gemini (search grounding) and WebSearch simultaneously, same architecture proven in `/pi-fact-check`. If Gemini times out or returns 429, WebSearch results cover the gap. Claude synthesizes all available sources with URL attribution
- **Source URLs in research reports** — Gemini prompted to return source URLs; WebSearch URLs included in final report. Claims without sources marked as (unverified)
- **Provider Status table** — research reports now begin with a track status table (Gemini ✅/⚠️, WebSearch ✅/⚠️, Claude ✅ always)

### Structured error diagnostics

- **Error classification in shell scripts** — `call-gemini.sh` and `call-codex.sh` now classify errors into 7 categories: `TIMEOUT`, `RATE_LIMIT`, `AUTH_ERROR`, `PERMISSION`, `SANDBOX` (Codex only), `NETWORK`, `CLI_ERROR`, plus `CLI_NOT_FOUND` for missing binaries
- **Bash regex over grep** — error classification uses `[[ "${err_text,,}" =~ pattern ]]` instead of `echo | grep -qi`, eliminating subshell forks on the error path and avoiding a `set -euo pipefail` edge case
- **PERMISSION class** — new error category for filesystem permission denied (previously misclassified as AUTH_ERROR in both scripts). `call-codex.sh` reordered: SANDBOX now matches before AUTH_ERROR, preventing "permission denied" from triggering wrong recovery guidance
- **CLI_NOT_FOUND class** — binary resolution failures now emit the same structured `Error: CLI_NOT_FOUND:` prefix as runtime errors, so downstream commands can parse failure reason consistently

### Unified failure handling across all commands

All 10 commands updated with consistent failure handling:

- **Specific failure reasons** — every failure message now includes the error classification from stderr (e.g., "⚠️ Gemini unavailable (RATE_LIMIT) — ...") instead of generic "unavailable"
- **Alternative command suggestions** — when a provider fails, the message suggests a relevant alternative:
  - `/pi-ask-codex` / `/pi-ask-gemini` → suggest `/pi-askall`
  - `/pi-code-review` → suggest `/pi-multi-review`
  - `/pi-ui-review` → suggest `/pi-multi-review`
- **Full error category lists** — all command docs now list the complete set of error categories (no more "etc." shortcuts), matching the actual script output. Gemini commands include PERMISSION; Codex commands include SANDBOX
- **Never abort** — consistent across all commands: always produce output, even if all providers fail

### Analysis context

- Gemini CLI log analysis (628 log entries, Feb 24 – Mar 27): average latency increased ~30% post-March 25 service update, 6 timeout incidents concentrated on API deployment dates (Mar 18: 60% failure rate, Mar 25: 22% failure rate)
- `/pi-research` and `/pi-fact-check` confirmed as architecturally distinct (exploratory vs verification) — not merged, but `/pi-research` elevated to the same resilience tier

## v0.10.3 (2026-03-26)

**Fact-Check Dual-Track** — Gemini + WebSearch race eliminates dead-wait time.

- **Dual-track search architecture** — `/pi-fact-check` now launches Gemini (search grounding) and WebSearch simultaneously instead of sequential fallback. Whichever returns first is usable immediately; both results merge for stronger source convergence
- **Batch size optimization** — Gemini batches reduced from 5 to 2 claims each (search grounding serializes internally; smaller batches complete within timeout)
- **Timeout fix** — replaced `perl alarm` with Bash tool timeout parameter (fixes orphan process on macOS, removes permission allowlist dependency)
- **Convergence-based confidence** — new report format with source convergence scoring (🟢 High/🟡 Medium/🟠 Single/🔴 Conflicting) and 6-tier source ranking (L1 official records through L6 community)
- **URL validation** — Step 4.5 verifies Gemini-sourced URLs via WebFetch, downgrades verdict on hallucinated/fabricated sources, triggers full WebSearch fallback if >50% fail
- **Editorial chain dedup** — same-origin sources (e.g., AP wire republished by 5 outlets) collapsed to 1 independent source for accurate convergence counting
- **README updates** — bilingual documentation updated to reflect dual-track architecture, cost estimation, and degradation path

## v0.10.2 (2026-03-22)

**Score Transparency & README Rewrite** — show your work, sharpen claims.

- **Score transparency (Show Your Work)** — all 3 review commands (`/pi-code-review`, `/pi-multi-review`, `/pi-ui-review`) now end with a `show scores` affordance. Users can request a full factor breakdown for every finding, showing exactly how each confidence score was calculated (base 40, applicable factors, arithmetic)
- **README rewrite** — "The Problem" / "The Solution" sections rewritten with clearer narrative: F1 noise → cross-provider triangulation → evidence-based scoring → local-first. New "Why Trust the Findings?" section explains the difference between LLM self-assessment and deterministic evidence-based scoring
- **Accuracy fixes** — F1-to-false-positive claim corrected (removed unsupported ratio), Anthropic plugin comparison softened to factual statement, determinism claims qualified to "core formula" per spec §2.2
- **Bilingual affordance** — score transparency hint line now bilingual (EN/zh-TW) for international users
- **Gemini CLI service update notice** — added Prerequisites notice about Google's March 25, 2026 changes (free accounts limited to Flash models)
- **Acknowledgments section** — added to both READMEs, crediting newtype-os/super-fact-checker

## v0.10.1 (2026-03-19)

**Fact-Check Rewrite** — original methodology, unified English.

- **Rewritten `/pi-fact-check` prompt** — replaced external methodology with original cross-provider approach: natural language claim extraction, source preference ordering, 4 verdicts (Verified / Imprecise / Incorrect / Unverifiable), 5 cross-verification dimensions
- **Adversarial evidence** — new verification dimension: court filings, regulatory actions, and competitor analyses that implicitly confirm facts carry highest confidence (survived hostile scrutiny)
- **Unified English** — all prompt content now in English, consistent with other commands
- **Simplified** — 186 → 121 lines without losing functionality

## v0.10.0 (2026-03-19)

**New Command: Fact-Check**

- **New `/pi-fact-check` command** — cross-provider fact verification using Gemini (Google search) for source discovery and Claude for cross-verification. Two providers, two roles: Gemini finds evidence, Claude judges it
- **Gemini-only** — no Codex. Fact-checking is an evidence-based task; Codex has no web search and would not add verification value
- **Graceful degradation** — Gemini timeout (90s) → WebSearch fallback → Claude training data. Never aborts
- **Save results** — optional save to `.claude/pi-fact-check/<slug>.md`

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
