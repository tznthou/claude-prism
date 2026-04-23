---
command: pi-multi-review
description: Triple-provider adversarial review — Codex + Gemini + Claude synthesis
---

# Multi-Provider Adversarial Review (Codex + Gemini + Claude)

Send the same code to both Codex and Gemini for **adversarial review with divided attack surfaces**, then Claude synthesizes. Codex attacks security & data integrity; Gemini attacks design, UX & maintainability. **Three adversarial perspectives, maximum blind spot elimination.**

## Execution

> **Dispatch rules (v0.13.0+)**: For **parallel provider consultation**, use the `Agent` tool with `subagent_type: "general-purpose"` to spawn two parallel sub-agents — NOT two `Bash` tool calls in a single main-conversation response. Main-conversation Bash is a structural FIFO queue: the second Bash waits for the first to finish (`delta ≈ first_exec` precisely, measured N=7 across two capacity slots), which defeats the parallel intent. Sub-agent fan-out dispatches Bash calls truly in parallel (median delta 2.8s, N=13), saving roughly 28% wall-clock on a two-provider call.
>
> Inside each sub-agent, run `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with `timeout: 600000` (Bash tool's 10-minute ceiling). Do not use `&`, `nohup`, or `run_in_background: true` — Claude Code 2026-04+ has an auto-background child-lifecycle regression that silently kills the child (output file stays 0 bytes). If a sub-agent's Bash returns empty stdout, fall back to reading `~/.claude/logs/pi-{codex,gemini}-last.out` (the wrapper's `tee` safety net).

### 1. Determine review scope

Same as `/pi-code-review`, based on `$ARGUMENTS`:
- No args → staged changes
- File path → specified file
- `--diff` → unstaged changes
- `--pr` → PR diff
- `--verbose` → also show issues that were filtered out (< 80 confidence) with their scores

### 2. Get the code

Use Bash / Read tool. **The same code goes to both providers.**

### 2.3 Gather project guidelines

Search for project guideline files to use as compliance context:

```bash
# Check common locations for guideline files
for f in CLAUDE.md .claude/CLAUDE.md Agents.md .claude/Agents.md; do
  [ -f "$f" ] && echo "=== $f ===" && cat "$f"
done
```

- If **any** guideline files are found, include them in both provider prompts (Step 3) and Claude synthesis (Step 6).
- If **none** are found, skip the guideline compliance dimension entirely.

### 2.4 Gather historical PR comments (--pr mode only)

When using `--pr` mode, search for recurring review patterns on the same files:

1. Get files in this PR: `git diff main...HEAD --name-only`
2. Find recent merged PRs: `gh pr list --state merged --limit 10 --json number,title`
3. For each (up to 5), fetch review comments on the same files:
   ```bash
   gh api "repos/{owner}/{repo}/pulls/NUMBER/comments" \
     --jq '.[] | select(.path == "TOUCHED_FILE") | {path, body}'
   ```
4. Include found comments as additional context in **both** provider prompts (Step 3) and Claude synthesis (Step 6), prefixed with:
   "Historical Review Context (previous review comments on the same files — recurring issues are high-confidence signals):"

If no historical comments exist or `gh` is not available, skip silently.

### 2.5 Detect review domain (smart routing)

Determine the domain of the changes to guide synthesis weighting in Step 6.

Based on the review scope determined in Step 1, get the file list and pipe it to the domain detection script:

```bash
# For staged changes:
git diff --cached --name-only | ~/.claude/scripts/detect-domain.sh

# For file review:
echo "<filepath>" | ~/.claude/scripts/detect-domain.sh

# For unstaged changes:
git diff --name-only | ~/.claude/scripts/detect-domain.sh

# For PR diff:
git diff main...HEAD --name-only | ~/.claude/scripts/detect-domain.sh
```

The script outputs one of: `frontend`, `backend`, or `fullstack`. Store this result for use in Step 6.

If the script is not found or fails, default to `fullstack` (balanced weighting) and continue.

### 3. Adversarial review (parallel via sub-agent fan-out)

**Sub-agent fan-out required** — see Dispatch rules above. The two providers receive **different attack-surface framings** (Codex attacks security/data integrity; Gemini attacks design/UX/maintainability), so each gets its own temp file.

**Step 3a — Build each provider's adversarial prompt.** Both share a common template; only the focus statement and attack surface list differ.

Shared template:

```
You are performing an adversarial code review focused on <FOCUS>.
Your job is to break confidence in this change, not to validate it. Default to skepticism.

Attack surface — prioritize these failure modes:
<ATTACK_SURFACE_LIST>
$(if guidelines found)8. Project guideline violations (see guidelines below)$(end if)

Scope constraint: Focus on the diff provided. Do not speculate about code outside the diff unless directly referenced by the changed lines.

$(if guidelines found)
Project Guidelines:
--- BEGIN GUIDELINES ---
$(guideline content from Step 2.3)
--- END GUIDELINES ---
$(end if)

$(if historical comments found from Step 2.4)
Historical Review Context (previous review comments on the same files — recurring issues are high-confidence signals):
$(historical comments)
$(end if)

Finding bar — every finding MUST answer:
1. What can go wrong?
2. Why is this code path vulnerable?
3. What is the likely impact?
4. What concrete change would reduce the risk?

DO NOT flag:
- Pre-existing issues not introduced in this diff
- Issues linters/formatters would catch (eslint, prettier, etc.)
- Style preferences without guideline backing or concrete failure scenario
- Lines with explicit lint-ignore / noqa / @ts-ignore comments

Calibration: Prefer one strong finding over several weak ones. If the change looks safe, say so directly.

Final self-check: Verify each finding is adversarial (not stylistic), tied to concrete code, and plausible under a real failure scenario.

Label each issue with severity (🔴/🟡/🟢) and line numbers.
End with an overall score (1-10).

Code:
$(code)
```

**Codex substitutions** (security & data integrity focus):
- `<FOCUS>` → `security, data integrity, and infrastructure resilience`
- `<ATTACK_SURFACE_LIST>`:
  ```
  1. Auth, permissions, tenant isolation, trust boundary violations
  2. Data loss, corruption, duplication, irreversible state changes
  3. Rollback safety, retry logic, partial failure, idempotency gaps
  4. Race conditions, ordering assumptions, stale state, re-entrancy
  5. Version skew, schema drift, migration hazards
  6. Observability gaps that would hide failures in production
  7. Inline annotation violations (IMPORTANT/WARNING/FIXME/TODO/NOTE comments)
  ```

**Gemini substitutions** (design, UX & maintainability focus):
- `<FOCUS>` → `design quality, UX impact, and long-term maintainability`
- `<ATTACK_SURFACE_LIST>`:
  ```
  1. Empty-state, null, timeout, degraded dependency behavior from a user's perspective
  2. Accessibility violations, broken responsive behavior, inconsistent UI states
  3. API contract mismatches, missing error feedback to users, silent failures
  4. Abstraction leaks, tight coupling, violation of single responsibility
  5. Missing or misleading test coverage that creates false confidence
  6. Breaking changes to public interfaces without migration path
  7. Inline annotation violations (IMPORTANT/WARNING/FIXME/TODO/NOTE comments)
  ```

**Step 3b — Persist each prompt to its own temp file**:

1. Bash: `CODEX_PROMPT=$(mktemp -t prism-review-codex-XXXXXX.md) && GEMINI_PROMPT=$(mktemp -t prism-review-gemini-XXXXXX.md) && echo "CODEX=$CODEX_PROMPT" && echo "GEMINI=$GEMINI_PROMPT"` — capture both paths.
2. Use the Write tool twice — write the Codex-focus prompt to `$CODEX_PROMPT` and the Gemini-focus prompt to `$GEMINI_PROMPT`.

**Step 3c — Send ONE response with two `Agent` tool calls in parallel.** Both use `subagent_type: "general-purpose"`. Fill `<CODEX_PROMPT>` / `<GEMINI_PROMPT>` with the actual paths from Step 3b.

**Codex agent** (description: "Codex adversarial review — security focus"):

```
Task: run one foreground-synchronous Bash command and return its output verbatim.

Step 1. Run this exact Bash command (timeout 600000 ms; no `&`, `nohup`, or `run_in_background: true`):

    start_ts=$(date +%s)
    wrapper_out=$(~/.claude/scripts/call-codex.sh "adversarial review" < "<CODEX_PROMPT>" 2>&1)
    rc=$?
    end_ts=$(date +%s)
    if [ -z "$wrapper_out" ]; then
        wrapper_out=$(cat ~/.claude/logs/pi-codex-last.out 2>/dev/null)
        [ -n "$wrapper_out" ] && echo "[FALLBACK: wrapper stdout was empty — loaded from pi-codex-last.out]"
    fi
    printf '%s\n' "$wrapper_out"
    echo "===META==="
    echo "rc=$rc"
    echo "runtime=$((end_ts - start_ts))s"
    echo "response_bytes=$(wc -c < ~/.claude/logs/pi-codex-last.out 2>/dev/null || echo NA)"

Two design notes on this Bash shape:
- `< "<CODEX_PROMPT>"` feeds the prompt directly to the wrapper's stdin — NO `cat |` pipe. Without `set -o pipefail`, a pipeline's `$?` is only the tail command's exit code, so a missing / unreadable prompt file would silently run the wrapper on empty stdin. Direct redirect keeps `$?` as the wrapper's real rc.
- The `wrapper_out` capture lets the emptiness check run BEFORE the META block is printed. If we echoed META first, stdout would never be empty (META would always fill it), so the `pi-codex-last.out` fallback for silent-kill / auto-bg regressions would never trigger.

Step 2. Return to me: the complete printed output verbatim (do NOT summarize, paraphrase, or reformat the Codex review — it will feed Claude's synthesis and confidence scoring with full fidelity), including the META block. If the Bash command printed a `[FALLBACK: ...]` line, relay that too — it signals the wrapper was silently killed and the response came from the tee safety net. If rc != 0, include any stderr — the wrapper classifies failures as TIMEOUT / RATE_LIMIT / AUTH_ERROR / SANDBOX / NETWORK / CLI_ERROR / CLI_NOT_FOUND.

Only use Bash and Read tools.
```

**Gemini agent** (description: "Gemini adversarial review — design focus"):

Same template as the Codex agent, with these substitutions:
- Replace `<CODEX_PROMPT>` → `<GEMINI_PROMPT>`
- Replace `~/.claude/scripts/call-codex.sh` → `~/.claude/scripts/call-gemini.sh`
- Do NOT set or override `GEMINI_MODEL` in the Bash command — the user's environment passes through to the sub-agent, then to `call-gemini.sh`, then to the CLI. Skills do not pin model tiers on the user's behalf.
- Fallback file: `~/.claude/logs/pi-gemini-last.out`
- Classifier list adds PERMISSION (Gemini-specific) and has no SANDBOX.

Both agents dispatch in parallel because they share a single main-conversation response. When both return, proceed to Step 4.

### 4. Handle partial failures (graceful degradation)

If one provider fails (script exits non-zero or returns an error message):
- **Do NOT abort the review.** Continue with the remaining providers.
- Claude always participates, so at minimum you have Claude + one external provider.
- Include the specific failure reason from stderr (TIMEOUT, RATE_LIMIT, AUTH_ERROR, SANDBOX, PERMISSION, NETWORK, CLI_ERROR, or CLI_NOT_FOUND).
- In the output, clearly note: "⚠️ [Provider] unavailable ([reason]) — continuing with [other provider] + Claude."
- If **both** external providers fail, Claude performs a solo review and notes: "⚠️ Both external providers unavailable ([Codex reason] / [Gemini reason]) — single-perspective review. For single-provider review, try `/pi-code-review` (Codex) or `/pi-ui-review` (Gemini) when they recover."

If a sub-agent reported empty stdout, it should already have fallen back to reading `~/.claude/logs/pi-codex-last.out` or `~/.claude/logs/pi-gemini-last.out` (the wrapper's `tee` safety net). If even that file is 0 bytes, treat the provider as unavailable and note the failure reason in the Provider Status table.

### 5. Handle non-conforming output

External providers may not follow the requested format (no emoji severity, no 1-10 score, pure prose, etc.). When this happens:
- **Do NOT discard the response or force it into the template.** Extract actionable insights from the raw text.
- If a provider gave no numeric score, omit that cell from the Score Comparison table (use "—" instead) and note "score not provided by provider."
- For the Consensus/Divergence analysis, match issues by **semantic similarity** rather than format — the same bug described in different words still counts as consensus.

### 6. Claude synthesis

After receiving results (from however many providers succeeded), Claude performs integrated analysis using the domain detected in Step 2.5.

#### Confidence scoring & filtering

Before synthesis, Claude scores **every** issue from all providers using the [Confidence Scoring Framework](../spec/confidence-scoring-v1.md). **Only issues scoring ≥ 80 enter the synthesis.**

##### Evidence extraction

For each issue from every provider, extract these fields:

1. **line_numbers** — Does the issue reference specific line numbers in the diff? (not vague "around line X")
2. **is_new_code** — Is the issue about code **introduced in this diff**? (not pre-existing code)
3. **rule_citation** — Does it cite a concrete rule (OWASP, language spec, project guideline, linter rule name)?
4. **has_reproduction** — Does it describe a reproducible scenario with steps, input, and expected vs actual outcome?
5. **flagged_by_providers** — Which providers flagged this issue? Match by semantic similarity (same underlying problem, regardless of wording). Two or more independent providers = consensus.
6. **references_removed_code_only** — Does it **solely** concern code the diff removes, with no impact on remaining code?
7. **is_linter_catchable** — Would a linter/formatter catch this? (only applies if the project has such tooling configured)
8. **is_subjective_style** — Is it a subjective style preference with no guideline backing? (distinguish from: readability backed by language idioms, maintainability with concrete impact, documented team conventions)
9. **references_exist_in_codebase** — Do all files, symbols, and APIs referenced in the issue actually exist? **Verify using Glob/Grep tools** — do not assume.

Each field is binary: applies or doesn't. When evidence is ambiguous, treat the factor as **not applicable**.

##### Hallucination verification

If an issue references a specific file, function, class, or API:
- Use Glob/Grep to verify the reference exists in the codebase
- If any referenced symbol does not exist → mark `references_exist_in_codebase = false`
- This check is mandatory — hallucinated references are the strongest noise signal

##### Score calculation

| Factor | Score Impact |
|--------|-------------|
| References specific line numbers in the diff | +25 |
| Code **introduced in this diff** (not pre-existing) | +25 |
| Cites a concrete rule (OWASP, guideline, language spec) | +20 |
| Describes a reproducible scenario (steps, input, consequence) | +15 |
| Multiple providers flagged the same issue (consensus) | +20 |
| **Solely** concerns code the diff removes, with no impact on remaining code | −30 |
| Linter/formatter would catch it (and project has such tooling) | −25 |
| Subjective style preference with no guideline backing | −25 |
| References a file, symbol, or API that **does not exist** in the codebase | −50 |

```
score = clamp(40 + sum(applicable_factors), 0, 100)
```

**Critical rule**: Scoring must be **evidence-based**, not opinion-based. If an issue has strong evidence (line numbers + concrete scenario + cited rule) but Claude "disagrees" with the finding, it still scores high. The goal is noise filtering, not Claude vetoing cross-provider insights.

#### Guideline compliance (if guidelines found in Step 2.3)

Score guideline violations separately (no double-dip with "cites a rule" — use the higher bonus):
- Violation explicitly mentioned in guideline text → confidence +30 (replaces +20 rule citation if both apply)
- Violation inferred but not explicitly stated → confidence +10
- Only include violations that reference a **specific rule** from the guideline files.

#### Domain-aware weighting

Apply provider authority based on the detected domain:

| Domain | Gemini Weight | Codex Weight | Rationale |
|--------|--------------|--------------|-----------|
| `frontend` | **Higher authority** | Standard | Gemini excels at UI/UX, accessibility, design patterns |
| `backend` | Standard | **Higher authority** | Codex excels at algorithms, security, API design |
| `fullstack` | Equal | Equal | Balanced — default behavior |

**How to apply weighting:**
- When providers **agree** → domain weighting is irrelevant (consensus is consensus).
- When providers **disagree** → the domain-authoritative provider's opinion gets the benefit of the doubt. Note: "Weighted toward [Provider] (domain: [domain])."
- When the domain-authoritative provider raises an issue **alone** → treat it with higher confidence than a non-authoritative solo finding.
- **Never discard** any provider's finding due to weighting. Weighting affects synthesis priority, not inclusion.

#### 6.1 Consensus (multiple providers flagged, ≥ 80 confidence)
Issues that two or more reviewers identified — **high confidence, fix first**.

#### 6.2 Divergence (only one flagged, ≥ 80 confidence)
Issues only one provider raised. Claude judges:
- Whether it's a real issue
- Why the others missed it (blind spot analysis)
- **Apply domain weighting**: if the domain-authoritative provider raised it, lean toward treating it as valid.

#### 6.3 Guideline compliance (if guidelines found)
Violations of project guidelines (`CLAUDE.md`, `Agents.md`) that passed confidence filtering. Group by source file.

#### 6.4 Claude's independent perspective
Issues no other provider caught but worth noting.

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

#### 6.5 Filtered out (not shown by default)
Issues that scored < 80 confidence are omitted by default.

If `--verbose` was specified, add a **Filtered Issues** section after the main results:
```
### Filtered Issues (< 80 confidence)
| # | Issue | Score | Provider | Reason filtered |
|---|-------|-------|----------|-----------------|
| 1 | Brief description | 65 | Codex | subjective style (-25) |
| 2 | Brief description | 40 | Gemini | no line numbers, no evidence |
| 3 | Brief description | 0 | Codex | hallucinated reference (-50) |
```

#### Score transparency (Show Your Work)

After presenting all results, end with this line:

> 💡 Type `show scores` to see how each finding was scored. / 輸入 `show scores` 查看每個 finding 的分數計算過程。

When the user responds with `show scores` (or similar intent like "show breakdown", "how was it scored", "分數怎麼算的"), present the factor breakdown for every finding:

```
### Score Breakdown

**[issue title]** (Codex) — Score: [score]
├─ Base: 40
├─ Specific line numbers: +25
├─ New code in this diff: +25
├─ OWASP A03:2021 citation: +20
├─ Multi-provider consensus: +20
└─ Final: 100 (clamped)

**[issue title]** (Gemini) — Score: [score]
├─ Base: 40
├─ Specific line numbers: +25
├─ Subjective style preference: −25
└─ Final: 40
```

Include both shown (≥80) and filtered (<80) findings. For each finding, list only factors that actually applied (skip +0 factors). Include the provider source. Show the arithmetic so the user can verify.

### 7. Output format

```
## Multi-Provider Review Results

### Provider Status
| Provider | Status |
|----------|--------|
| Codex | [available/unavailable — reason] |
| Gemini | [available/unavailable — reason] |
| Claude | available (always) |

### Domain & Weighting
| Domain | Provider Authority |
|--------|-------------------|
| [frontend/backend/fullstack] | [Gemini-weighted / Codex-weighted / Balanced] |

### Score Comparison
| Provider | Score | Focus Area |
|----------|-------|------------|
| Codex | X/10 or — | ... |
| Gemini | Y/10 or — | ... |
| Claude | Z/10 | ... |

### Consensus Issues (high confidence, fix first)
(When an issue has a concrete fix, use a GitHub suggestion block — see format below)
...

### Divergent Issues (needs judgment)
...

### Guideline Compliance
(Only if guideline files were found in Step 2.3)
...

### Claude Supplements
...

### Confidence Summary
| Tier | Count |
|------|-------|
| High (≥ 90) | N |
| Solid (80–89) | N |
| Filtered (< 80) | N (use --verbose to see) |

### Filtered Issues (--verbose only)
(Table of filtered issues with scores and filter reasons — omit this section if --verbose was not specified)

### Action Items
1. ...
2. ...
```

### 8. Record review insights

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
  "confidence": 85,
  "title": "Brief one-line description of the issue",
  "source": "consensus|codex-only|gemini-only|claude-only"
}
```

Rules:
- Only record issues that **passed the confidence filter** (≥ 80)
- Map emoji severity to strings: 🔴→critical, 🟡→medium, 🟢→suggestion
- If a provider didn't give structured severity, infer from context (e.g., "security vulnerability" → critical)
- Use `"guideline"` category for project guideline violations (`CLAUDE.md` / `Agents.md`)
- `source` reflects which providers flagged it: consensus (2+), or single-provider
- Keep `title` under 80 chars — enough to identify the pattern, not a full description
- Create the directory if it doesn't exist: `mkdir -p ~/.claude/logs`
