---
command: pi-multi-review
description: Triple-provider adversarial review — Codex + Gemini + Claude synthesis
---

# Multi-Provider Adversarial Review (Codex + Gemini + Claude)

Send the same code to both Codex and Gemini for **adversarial review with divided attack surfaces**, then Claude synthesizes. Codex attacks security & data integrity; Gemini attacks design, UX & maintainability. **Three adversarial perspectives, maximum blind spot elimination.**

## Execution

> **Dispatch rules (v0.13.0+)**: For **parallel provider consultation**, use the `Agent` tool with `subagent_type: "general-purpose"` to spawn two parallel sub-agents — NOT two `Bash` tool calls in a single main-conversation response. Main-conversation Bash is a structural FIFO queue: the second Bash waits for the first to finish (`delta ≈ first_exec` precisely, measured N=7 across two capacity slots), which defeats the parallel intent. Sub-agent fan-out dispatches Bash calls truly in parallel (median delta 2.8s, N=13), saving roughly 28% wall-clock on a two-provider call.
>
> Inside each sub-agent, run `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with `timeout: 600000` (Bash tool's 10-minute ceiling). Do not use `&`, `nohup`, or `run_in_background: true` — Claude Code 2026-04+ has an auto-background child-lifecycle regression that silently kills the child (output file stays 0 bytes). If a sub-agent's Bash returns empty stdout, the Bash template below falls back to reading the caller-owned `$OUT_PATH` file (v0.14.3+, wrapper `tee`s here via `CLAUDE_PRISM_OUT_TMP`).

### 0. Pin the working directory

Before any other step, run `pwd` and keep the result as `<WORKDIR>`. Sub-agents start in whatever directory the main conversation is in when it dispatches them; if you `cd` elsewhere in between (a scratch directory to try something out, say), the wrapper would run outside this project. The template in Step 3c sends each sub-agent back to `<WORKDIR>` first.

### 1. Determine review scope

Same as `/pi-code-review`, based on `$ARGUMENTS`:
- No args → staged changes
- File path → specified file
- `--diff` → unstaged changes
- `--pr` → PR diff
- `--recheck` → this run reviews the fixes for the previous round's findings. Combine it with any scope above (e.g. `--recheck --diff`). Only Codex is consulted (Step 3c), and this is the last round for this change (Step 7, Action Items)

### 2. Get the code

Use Bash / Read tool. **The same code goes to both providers.**

Record a hash of the code as `<DIFF_HASH>`, using the same source as the code itself, so the provider that reports second can tell whether it reviewed what is in the tree now (Step 7.1):

```bash
git diff --cached | shasum      # no args (staged changes)
shasum < "<filepath>"           # file review
git diff | shasum               # --diff
git diff main...HEAD | shasum   # --pr
```

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
You get exactly one turn: do not ask clarifying questions.
If context is missing, state your assumptions and answer anyway.

You are performing an adversarial code review focused on <FOCUS>.
Your job is to break confidence in this change, not to validate it. Default to skepticism.

Attack surface — prioritize these failure modes:
<ATTACK_SURFACE_LIST>
$(if guidelines found)8. Project guideline violations (see guidelines below)$(end if)

Skip attack surfaces that do not apply to this diff — do not force findings from inapplicable surfaces.

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

DO NOT flag:
- Pre-existing issues not introduced in this diff
- Issues linters/formatters would catch (eslint, prettier, etc.)
- Style preferences without guideline backing or concrete failure scenario
- Lines with explicit lint-ignore / noqa / @ts-ignore comments

Output format — one block per finding, exactly this structure:

[CRITICAL|MEDIUM|SUGGESTION] file:line — one-line title
- Failure scenario: what goes wrong, and why this code path allows it
- Impact: the likely consequence
- Fix: the concrete change that reduces the risk

At most 8 findings — if you found more, keep the highest-impact 8. Prefer one strong finding over several weak ones; do not dilute serious issues with filler.

If you report no findings, the verdict still needs evidence — before it, list what you examined in the code below:

Checked:
- <file or function under review> — <the failure modes above you tested it against>

End with exactly one line:
VERDICT: safe | needs-fixes | do-not-merge

A verdict on its own is not a complete review. Do not invent findings to seem thorough — when nothing holds up as a real issue, the Checked list followed by VERDICT: safe is the complete answer.

Final self-check: verify each finding is adversarial (not stylistic), tied to concrete code, and plausible under a real failure scenario.

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
- **Domain-aware surface trim**: if the domain detected in Step 2.5 is `backend`, omit item 2 (accessibility/responsive/UI states — inapplicable to backend-only diffs) and renumber the remaining items. For `frontend` and `fullstack`, keep the full list.
- **No tools**: do not write a no-tools instruction into the Gemini prompt. The Gemini agent's Bash command passes `--no-tools` (see the Gemini agent substitutions below), and `call-gemini.sh` prepends the line itself. Gemini runs through agy in headless mode, where a tool call that needs permission is auto-denied and the turn ends with no output (EMPTY_OUTPUT). Codex gets no such flag — it keeps its repository access.

**Recheck additions** (only with `--recheck`; Codex prompt only):
- **Gather the previous round's findings.** Take them from the previous `/pi-multi-review` report in this conversation: every finding that report listed, from every provider (Codex, Gemini, and Claude's own supplements), with its provider, severity, `file:line`, title, and one-line failure scenario. If there is no previous report in this conversation, ask the user once to paste it. If they do not, run the recheck as a plain review and say in the report: "No previous findings available — fixes were not checked item by item."
- **Insert this block into the Codex prompt immediately before the `Code:` line:**

  ```
  This is a recheck: the code below is meant to fix the findings from the previous review round.

  Previous findings:
  --- BEGIN PREVIOUS FINDINGS ---
  <one line per finding: [provider] [severity] file:line — title — failure scenario>
  --- END PREVIOUS FINDINGS ---

  Before your own review, go through every previous finding — including those outside your focus area — and output one line for each:
  [Fixed|Still present|Not verified] file:line — title — what in the current code shows it
  Use Not verified when the code the finding points at is not in the diff below and you cannot check it, or when you cannot tell. Do not leave a previous finding out.

  Then review the code below for new problems as instructed above.
  ```

**Step 3b — Persist each prompt to its own temp file**:

1. Bash: `CODEX_PROMPT=$(mktemp -t prism-review-codex-XXXXXX.md) && GEMINI_PROMPT=$(mktemp -t prism-review-gemini-XXXXXX.md) && echo "CODEX=$CODEX_PROMPT" && echo "GEMINI=$GEMINI_PROMPT"` — capture both paths.
2. Use the Write tool twice — write the Codex-focus prompt to `$CODEX_PROMPT` and the Gemini-focus prompt to `$GEMINI_PROMPT`.

**Step 3c — Send ONE response with two `Agent` tool calls in parallel.** Both use `subagent_type: "general-purpose"`. Fill `<CODEX_PROMPT>` / `<GEMINI_PROMPT>` with the actual paths from Step 3b, and `<WORKDIR>` with the path from Step 0 — do not run `pwd` again here.

**With `--recheck`, send only the Codex agent.** A recheck reviews fixes to findings already raised, and Codex is the provider whose findings held up when they were checked. Do not build or write the Gemini prompt in Steps 3a–3b, and do not spawn the Gemini agent. Gemini's Provider Status is `skipped (recheck)` and its Verdict Comparison cell is `—`. The report is written once Codex returns, so Step 7.1 does not apply. If Codex fails or is hollow, Claude reviews alone and notes "⚠️ Codex unavailable ([reason]) — recheck by Claude alone." Do not send Gemini in its place.

<!-- Keep in sync with commands/pi-askall.md and commands/pi-plan.md — the sub-agent Bash template shape is shared across these three skills. -->

**Why the Bash template below uses `wrapper_out=$(...) < "<PATH>"` rather than `cat <PATH> | ...`** (skill-maintainer note — NOT shipped to the sub-agent):
- `< "<PATH>"` direct redirect keeps `$?` as the wrapper's true exit code. A `cat | wrapper` pipeline without `set -o pipefail` would mask wrapper failure — `$?` on a pipe only reflects the tail command's rc, so a missing / unreadable prompt file could silently run the wrapper on empty stdin.
- The `wrapper_out=$(...)` capture lets the emptiness check run BEFORE the META block is printed. If we echoed META first, stdout would never be empty (META always fills it), so the `pi-*-last.out` fallback for silent-kill / auto-bg regressions would never trigger.

**Why the template opens with `cd "<WORKDIR>"`** (skill-maintainer note — NOT shipped to the sub-agent): sub-agents start in the main conversation's current working directory, and by the time Step 3c runs the main conversation may have `cd`'d into a scratch directory. Without the `cd`, the wrapper runs outside the project — Codex gets `--skip-git-repo-check` and Gemini's `--add-dir` points at the wrong directory.

**Codex agent** (description: "Codex adversarial review — security focus"):

```
Task: run one foreground-synchronous Bash command and return its output verbatim.

Step 1. Run this exact Bash command (timeout 600000 ms; no `&`, `nohup`, or `run_in_background: true`):

    cd "<WORKDIR>" || exit 1
    OUT_PATH=$(mktemp "${TMPDIR:-/tmp}/prism-codex-out-XXXXXX")
    start_ts=$(date +%s)
    # CLAUDE_PRISM_TIMEOUT=540: 60s buffer below 600s Bash tool ceiling so
    # wrapper soft-timeout fires first (structured error log). Keep in sync:
    # pi-plan.md, pi-multi-review.md, pi-code-review.md.
    wrapper_out=$(CLAUDE_PRISM_OUT_TMP="$OUT_PATH" CLAUDE_PRISM_TIMEOUT=540 CLAUDE_PRISM_CALLER=pi-multi-review ~/.claude/scripts/call-codex.sh "adversarial review" < "<CODEX_PROMPT>" 2>&1)
    rc=$?
    end_ts=$(date +%s)
    if [ -z "$wrapper_out" ]; then
        wrapper_out=$(cat "$OUT_PATH" 2>/dev/null)
        [ -n "$wrapper_out" ] && echo "[FALLBACK: wrapper stdout was empty — loaded from caller-owned OUT_TMP]"
    fi
    printf '%s\n' "$wrapper_out"
    echo "===META==="
    echo "rc=$rc"
    echo "runtime=$((end_ts - start_ts))s"
    echo "response_bytes=$(wc -c < "$OUT_PATH" 2>/dev/null || echo NA)"

Step 2. Return to me: the complete printed output verbatim (do NOT summarize, paraphrase, or reformat the Codex review — it will feed Claude's synthesis with full fidelity), including the META block. If the Bash command printed a `[FALLBACK: ...]` line, relay that too — it signals the wrapper was silently killed and the response came from the tee safety net. If rc != 0, include any stderr — the wrapper classifies failures as TIMEOUT / RATE_LIMIT / AUTH_ERROR / SANDBOX / NETWORK / EMPTY_OUTPUT / CLI_ERROR / CLI_NOT_FOUND. If the `cd` on the first line fails, return its error as is — do not change the path or re-run the command without the `cd`.

Only use Bash and Read tools.
```

**Gemini agent** (description: "Gemini adversarial review — design focus"):

Same template as the Codex agent, with these substitutions:
- Replace `<CODEX_PROMPT>` → `<GEMINI_PROMPT>`
- Replace `~/.claude/scripts/call-codex.sh` → `~/.claude/scripts/call-gemini.sh --no-tools` (the wrapper prepends the no-tools line; the diff is already in the prompt)
- Replace `prism-codex-out` → `prism-gemini-out` (in the `mktemp` template)
- Do NOT set or override `GEMINI_MODEL` in the Bash command — the user's environment passes through to the sub-agent, then to `call-gemini.sh`, then to the CLI. Skills do not pin model tiers on the user's behalf.
- Classifier list adds PERMISSION (Gemini-specific) and has no SANDBOX.

Both agents dispatch in parallel because they share a single main-conversation response. Sub-agents run in the background and each one notifies the main conversation when it finishes, so the two results arrive separately — Gemini usually several minutes after Codex.

**Report on the first result; do not wait for the second** (without `--recheck`; a recheck has only one provider). As soon as the first provider returns (usually Codex), run Steps 4–7 with that provider plus Claude and present the full report, with the other provider marked `pending` in Provider Status and Verdict Comparison. When the second provider's notification arrives, append its results under Step 7.1. If Gemini returns first, the roles swap: the report uses Gemini plus Claude, and Codex is the one marked `pending` and added in the addendum.

- If both results are already in when you start Step 4, write a single report with both and skip Step 7.1.
- If the first provider to return failed or is hollow (Steps 4–5), wait for the second before reporting, so the report is not Claude alone while a provider is still running.

### 4. Handle partial failures (graceful degradation)

Apply this step to the results that have returned so far. A provider that is still running is `pending`, not failed: it gets its own handling in Step 7.1 when it returns.

If one provider fails (script exits non-zero or returns an error message):
- **Do NOT abort the review.** Continue with the remaining providers.
- Claude always participates, so at minimum you have Claude + one external provider.
- Include the specific failure reason from stderr (TIMEOUT, RATE_LIMIT, AUTH_ERROR, SANDBOX, PERMISSION, NETWORK, EMPTY_OUTPUT, CLI_ERROR, or CLI_NOT_FOUND).
- In the output, clearly note: "⚠️ [Provider] unavailable ([reason]) — continuing with [other provider] + Claude."
- If **both** external providers fail (both have returned, neither usable), Claude performs a solo review and notes: "⚠️ Both external providers unavailable ([Codex reason] / [Gemini reason]) — single-perspective review. For a single-provider review, try `/pi-code-review` (Codex) when it recovers."

A provider whose reply is hollow (see Step 5) counts as failed here: continue without it, and give it the Provider Status `unavailable — DEGRADED (hollow response)`.

If a sub-agent reported empty stdout, it should already have fallen back to reading its caller-owned `$OUT_PATH` file (the wrapper's `tee` safety net, v0.14.3+). If even that file is 0 bytes, treat the provider as unavailable and note the failure reason in the Provider Status table.

### 5. Handle hollow and non-conforming output

**Check for a hollow response first.** A provider can exit 0 with a well-formed reply that still carries no review of the code under review: no finding that points at a location, and no `Checked:` entry or sentence naming a file or function under review (e.g. a lone `VERDICT: safe`, or just "No issues found."). Treat that provider as **DEGRADED** and handle it as unavailable under Step 4:
- Its VERDICT does not enter the Verdict Comparison table — put "—" and note "hollow response (DEGRADED)".
- It does not count toward consensus: a hollow "safe" is not agreement that the change is safe.
- Judge by content, not length: a short reply that names the code it checked is a real review. The sub-agent's `response_bytes` is only a rough first signal.

External providers may not follow the requested format (no severity tags, no VERDICT line, pure prose, etc.). When this happens:
- **Do NOT discard the response or force it into the template.** Extract actionable insights from the raw text.
- If a provider gave no VERDICT line, put "—" in that cell of the Verdict Comparison table and note "verdict not provided by provider."
- For the Consensus/Divergence analysis, match issues by **semantic similarity** rather than format — the same bug described in different words still counts as consensus.

### 6. Claude synthesis

After receiving results (from the providers that have returned and succeeded so far), Claude performs integrated analysis using the domain detected in Step 2.5.

#### Check each finding: Confirmed / Refuted / Unconfirmed

Before synthesis, Claude checks **every** finding from every provider against the code and gives it exactly one label:

| Label | Meaning |
|-------|---------|
| **Confirmed** | Claude checked the code and the failure scenario holds: the cited code exists, is introduced in this diff (or is directly used by it), and behaves as the finding says. |
| **Refuted** | Claude checked and it does not hold: a referenced file, symbol, or API does not exist (see Hallucination verification), the code does not behave as claimed, the issue is only in pre-existing code or only in code the diff removes, a linter the project runs would catch it, or it is a style preference with no guideline backing and no concrete failure. |
| **Unconfirmed** | The code available does not settle it — it depends on runtime configuration, code outside the repository, or behavior that would have to be run to observe. State what would settle it. |

**Label by checking the code, not by how the finding is worded or which provider raised it.** A finding Claude would not have raised itself is still Confirmed when the code bears it out — the label records what the check found, not Claude's opinion of the provider. When the evidence is ambiguous, use Unconfirmed, not Refuted.

##### Hallucination verification

If a finding references a specific file, function, class, or API:
- Use Glob/Grep to verify the reference exists in the codebase
- If any referenced symbol does not exist → the finding is **Refuted** (reason: "reference not found: `<name>`")
- This check is mandatory — a finding that cites code that is not there cannot be Confirmed

##### Where each label goes

- **Confirmed** and **Unconfirmed** findings go into the synthesis sections below (6.1–6.4), each showing its label; an Unconfirmed one also says what would settle it.
- **Refuted** findings stay out of those sections and are listed with a one-line reason at the end of the report (6.5), so a dropped finding is visible rather than silently filtered.

#### Guideline compliance (if guidelines found in Step 2.3)

Only include violations that cite a **specific rule** from the guideline files. Label them the same way: Confirmed when the guideline text states the rule and the code breaks it; Unconfirmed when the rule is only implied by the guideline.

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
- When the domain-authoritative provider raises an issue **alone** → check it first, and when the code supports either reading, prefer its reading.
- **Never discard** any provider's finding due to weighting. Weighting affects synthesis priority, not labels.

#### 6.1 Consensus (multiple providers flagged; Confirmed or Unconfirmed)
Issues that two or more reviewers identified — **fix the Confirmed ones first**.

#### 6.2 Divergence (only one flagged; Confirmed or Unconfirmed)
Issues only one provider raised. Claude judges:
- Whether it's a real issue
- Why the others missed it (blind spot analysis)
- **Apply domain weighting**: if the domain-authoritative provider raised it, lean toward treating it as valid.

#### 6.3 Guideline compliance (if guidelines found)
Violations of project guidelines (`CLAUDE.md`, `Agents.md`) that are not Refuted. Group by source file.

#### 6.4 Claude's independent perspective
Issues no other provider caught but worth noting.

#### 6.4a Previous findings (`--recheck` only)
Claude checks every previous finding against the current code itself (Read/Grep), with the same three labels — Fixed, Still present, Not verified — and does not just adopt Codex's label. Gemini's findings from the previous round need this most: Gemini is not consulted in a recheck, and Codex's focus is security, so Claude is the reviewer of record for them.
- When Claude's label and Codex's label agree, use it.
- When they disagree, Claude reads the code again and gives the label that holds, with the reason: "Codex: Fixed / Claude: Still present — line 7 still passes `$days` unquoted."
- If Codex failed, gave no label for a finding, or no previous findings were available, Claude's label stands alone; say so.
- Every Still present finding becomes an Action Item (Fix now or Defer, Step 7). Not verified findings are listed with what would verify them.

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

#### 6.5 Refuted findings
List every Refuted finding at the end of the report, one line each: provider, `file:line`, title, and why it does not hold. Nothing is hidden: the reader can see what was dropped and disagree.

### 7. Output format

Render provider text severity tags as emoji in the final output: CRITICAL→🔴, MEDIUM→🟡, SUGGESTION→🟢. Each finding shows its label after the title, e.g. `🔴 src/auth.ts:42 — SQL injection via unsanitized input — Confirmed`.

```
## Multi-Provider Review Results

### Provider Status
| Provider | Status |
|----------|--------|
| Codex | [available/unavailable — reason] |
| Gemini | [available/unavailable — reason/pending/skipped (recheck)] |
| Claude | available (always) |

### Domain & Weighting
| Domain | Provider Authority |
|--------|-------------------|
| [frontend/backend/fullstack] | [Gemini-weighted / Codex-weighted / Balanced] |

### Verdict Comparison
| Provider | Verdict | Focus Area |
|----------|---------|------------|
| Codex | safe / needs-fixes / do-not-merge / — | ... |
| Gemini | safe / needs-fixes / do-not-merge / — / pending | ... |
| Claude | safe / needs-fixes / do-not-merge | ... |

A verdict split between providers is a real signal — call it out explicitly and explain which reading the synthesis favors and why.

### Consensus Issues (fix Confirmed first)
(Each issue shows its label — Confirmed or Unconfirmed. When an issue has a concrete fix, use a GitHub suggestion block — see format below)
...

### Divergent Issues (needs judgment)
...

### Guideline Compliance
(Only if guideline files were found in Step 2.3)
...

### Claude Supplements
...

### Label Summary
| Label | Count |
|-------|-------|
| Confirmed | N |
| Unconfirmed | N |
| Refuted | N |

### Refuted Findings
| Provider | Finding | Why it does not hold |
|----------|---------|----------------------|
| Gemini | file:line — title | reference not found: `<name>` |

### Action Items
1. ...
2. ...
```

The template shows the usual order, Gemini `pending`; if Gemini returned first, Codex is the `pending` row. While a provider is `pending`, end the report with: "⏳ [Provider] is still reviewing — its findings will be added as an addendum."

**Two rounds at most per change.** A first-round report (no `--recheck`) ends its Action Items with: "After fixing these, run `/pi-multi-review --recheck` at most once." A `--recheck` report is the last round:
- Put a **Previous Findings** section right after Verdict Comparison, one row per previous finding (Step 6.4a):

  ```
  ### Previous Findings (recheck)
  | # | Finding | Raised by | Codex | Claude | Result |
  |---|---------|-----------|-------|--------|--------|
  | 1 | cleanup.sh:6 — unquoted $dir in rm -rf | Gemini | Fixed | Fixed | Fixed |
  | 2 | cleanup.sh:7 — find fails when logs/ missing | Gemini | Not verified | Still present | Still present |
  ```

- Mark every Action Item either **Fix now** or **Defer** (record it as a follow-up task — an issue or TODO — rather than leaving it in the report).
- Do not suggest another review round, and do not end with the `--recheck` line above.

### 7.1 Gemini addendum (the provider that returns second)

When the second provider's notification arrives after the report is out, do not rewrite the report. Append a section below it. This is usually Gemini; if Codex returned second, the same rules apply with the names swapped.

**First, check whether it reviewed the current code.** Fixes often start as soon as the report appears, so the late provider may have reviewed a diff that has since changed. Recompute the hash the same way as in Step 2 and compare it with `<DIFF_HASH>`:
- **Same hash** — add the findings as below.
- **Different hash** — open the addendum with "⚠️ Gemini reviewed an earlier version of the diff (`<DIFF_HASH>` → `<current hash>`)." Re-check every finding against the current code and label each one **Fixed**, **Still present**, or **Not verified** (it could not be checked again; if the code it points at has moved, say "code moved" in the reason). Still-present findings go through the rules below, including a Confirmed / Refuted / Unconfirmed label; Fixed and Not verified ones are listed with their fix status only.

**If it failed or is hollow** — timeout, empty output, or the DEGRADED test in Step 5 — add one line and stop: "⚠️ Gemini did not review this round ([reason])." Update its Provider Status row to the same reason.

**Otherwise:**
- Run its findings through Step 6 the same way as the first provider's, hallucination verification included.
- A finding that matches one already in the report (semantic match, as in Step 5): mark the existing entry "Gemini also flagged this" and treat it as consensus. Do not list it again.
- New findings that are not Refuted go in this section, using the Step 7 severity format with their label; Refuted ones get a one-line reason, as in 6.5.
- If it gave a VERDICT, add it to Verdict Comparison here, and call out a split with the earlier verdicts as Step 7 does.

```
### Gemini addendum
| Provider | Status |
|----------|--------|
| Gemini | [available/unavailable — reason] |

[⚠️ Gemini reviewed an earlier version of the diff (<old hash> → <current hash>).]

**Also flagged by Gemini:** [titles of existing entries now marked consensus]

**New findings**
...

**Verdict:** Gemini — safe / needs-fixes / do-not-merge / —

**Action Items (added)**
1. ...
```
