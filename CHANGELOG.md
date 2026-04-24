# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## v0.14.2 (2026-04-24)

**Wrapper: per-invocation `OUT_TMP` + atomic symlink.** Eliminates **byte-level `tee` interleaving** on the safety-net log file (pre-existing MEDIUM-severity finding). When two sub-agents or two Claude Code sessions invoke the same provider simultaneously, each gets its own `mktemp`-named output file; `pi-{codex,gemini}-last.out` becomes an atomic symlink to the latest invocation. The 10 `pi-*` skills are unchanged — the symlink is transparent to `cat`. **Known limitation**: this fix closes byte-level corruption; it does **not** solve fallback file-selection under concurrent same-provider invocation — the shared `pi-*-last.out` symlink still points to the last writer, so a skill that falls back to `cat` it may read another concurrent invocation's response. See Notes for the deferred env-var `OUT_TMP` contract that resolves this.

### Changed

- **`scripts/call-codex.sh` / `scripts/call-gemini.sh`** — `OUT_TMP` now points to a per-invocation `mktemp "${LOG_DIR}/pi-{codex,gemini}-last-XXXXXX"` file. After `wait "$LAST"` completes, `ln -sf "$(basename "$OUT_TMP")" "${LOG_DIR}/pi-{codex,gemini}-last.out"` atomically updates the stable path to the newest file. The `ln -sf` runs after `wait` (so the target is fully written) and is not conditioned on `rc` — partial output from soft-timeout or error paths still reaches the skill diagnostic fallback. Byte-sync mirror between the two scripts preserved; Keep-in-sync comment extended to cover the new block

### Security

- **Eliminates byte-level `tee` interleaving** (MEDIUM-severity finding). Prior behavior: concurrent writers to the fixed path `~/.claude/logs/pi-{codex,gemini}-last.out` interleaved at the byte level inside `tee`, corrupting any skill fallback that reads the file after the wrapper exits. The race was latent under v0.12.x because main-conversation Bash is a structural FIFO (empirically N=7, ratio 1.00, zero variance). v0.13.0 sub-agent fan-out introduced genuine parallelism (N=13, median dispatch delta 2.8s), activating the race pathway. After this change, each concurrent invocation owns its own `mktemp` file; byte-level interleaving is impossible
- **Remaining exposure — cross-session same-provider fallback file-selection**: the `pi-{codex,gemini}-last.out` symlink is a single stable pointer, "last `ln -sf` wins". If two Claude Code sessions on the same machine both invoke the same provider and one of them triggers the empty-stdout fallback, it may `cat` the symlink and read the *other* session's response. Frequency is low (requires cross-session + same-provider + empty-stdout concurrently) but non-zero. Mitigation before env-var contract ships: avoid running two Claude Code instances that concurrently use the same provider for unrelated tasks, or rely on sub-agent output fields rather than re-reading the symlink

### Testing

- **Race-regression test** — two parallel invocations under controlled fake-CLI fixtures on both Bash 5.3.9 (Homebrew) and Bash 3.2.57 (macOS system), both scripts. All four combinations verified to produce uncorrupted per-file output (exactly one BEGIN/END marker per file) with symlink pointing to a complete file. Test script resides under developer `/tmp/` (not shipped — requires fake-CLI injection and a throwaway log dir)
- Existing smoke suite unchanged at **43/43 passing**. Test 13 soft-timeout regression (6 cases) verified to still pass — `ln -sf` is placed after `wait` and before classification, so timeout path still writes the symlink before exiting 124

### Notes

- **Backward-compatible**: the 10 `pi-*` skill fallback reads (`cat ~/.claude/logs/pi-{codex,gemini}-last.out`) transparently follow the symlink. No skill markdown files changed
- **Not addressed** (deferred): same-provider 3+ fan-out within a single skill. The symlink-points-to-latest model is non-deterministic under 3+ concurrent same-provider invocations. Today's pi-* skills all use 1 Codex + 1 Gemini pairs; when a real 3+ fan-out pattern emerges, migration is an env-var `OUT_TMP` path-return contract (caller sets `OUT_TMP`, wrapper respects it, skill reads that specific path). Out of scope for this release
- **BSD `mktemp` template**: `XXXXXX` at end of template, no suffix. Matches the pre-existing verified pattern for `TIMEOUT_MARKER` in `call-*.sh`
- **Cleanup of stale `pi-*-last-*` files** is deferred — text logs are ~1–100 KB each; 50 calls/day = ~5 MB/day is not a storage problem. If needed later, cleanup will anchor to `install.sh` upgrade rather than a hot-path `find` on every wrapper invocation

## v0.14.1 (2026-04-24)

**Documentation restructure.** Split the 798-line README into a leaner 550-line entry point plus a `docs/` tree for deep-dive topics, and surface the empirical research behind the sub-agent fan-out design.

### Added

- **`## Empirical Foundation` section** in both README variants (~80 lines). Summarizes the N=36+ controlled experiments that identified Claude Code's main-conversation Bash tool as a structural FIFO queue (`delta/first_exec = 1.00` across 7 runs in two capacity windows) while sub-agent Bash is genuinely parallel (median dispatch delta 2.8s, N=13). Includes a MECE layer behavior matrix and a sequenceDiagram contrasting the anti-pattern vs the sub-agent fan-out design
- **`docs/research/bash-tool-parallelism.md`** (English, 102-line research summary). Publishes the experiment groups (A/B/C/F/D), the resulting layered conclusions, and the product decisions traced back to the data (sub-agent fan-out, asymmetric commit, rejection of fire-and-forget + polling, v0.14.0 soft-timeout as the next hardening step). Full per-run data and methodology deferred to a separate long-form write-up
- **`docs/` tree with six deep-dive topics** (bilingual): `observability`, `ci-cd`, `cost`, `supply-chain-security`, `privacy`, `reflections`. Each exists in native English and Traditional Chinese variants per the bilingual convention — not machine translations

### Changed

- **README.md / README.zh-TW.md both reduced from 798 → 550 lines** (-31%). Six heavy chapters (Observability / CI/CD Integration / Cost Estimation / Supply Chain Security / Privacy & Data Flow / Reflections) moved to `docs/`. The README now focuses on 30-second pitch + 10-minute onboarding; anything beyond that points into `docs/`
- **New `## Documentation` index section** at the end of both README variants lists all `docs/` entries with bilingual links

### Notes

- Runtime behavior, scripts, commands, and `checksums.sha256` are unchanged. `docs/` is not in the npm `files:` list, so this release is documentation-only for npm consumers
- Internal experiment scaffold (prompts, runner scripts, raw jsonl) remains in the gitignored `internal/` directory. Future publication as a reproducible scaffold is deferred

## v0.14.0 (2026-04-23)

**Soft-timeout wall-clock guard for `call-*.sh`.** Bounds provider-CLI execution to a configurable wall-clock limit so the script exits with a structured marker before the ~130s Claude Code harness watchdog SIGKILLs it silently. Addresses the F-group silent-death signature (N=1/7, evening-bad) identified in the 2026-04-20→21 bg-regression experiments.

### Added

- **`CLAUDE_PRISM_TIMEOUT` environment variable** (integer seconds, **range 1..3600**; default 110). Invalid values (non-integer, zero, negative, or above 3600) fall back to 110 with a `WARN` log entry. The upper bound prevents values that macOS BSD `sleep` rejects, which would otherwise kill the watcher subshell under `set -e` and silently disable the timeout guard entirely. Power users can widen per-invocation for known-long runs: `CLAUDE_PRISM_TIMEOUT=180 ./call-codex.sh "40KB review prompt"`
- **Soft-timeout mechanism** in both `scripts/call-codex.sh` and `scripts/call-gemini.sh`: background pipeline + watcher subshell + per-invocation marker file. On timeout, the watcher first confirms the pipeline is still alive (`kill -0 "$LAST"` gate, avoids boundary-race log pollution), then writes the marker, emits a `soft_timeout stage=exec elapsed_s=N` event to the shared log, and issues `pkill -TERM -P $$` to terminate all pipeline members (pipeline members are direct children of the parent shell in Bash's pipeline semantics). Parent's `EXIT` trap handles KILL-escalation plus marker/temp cleanup. Classification uses `rc in {143,137} && [[ -s "$TIMEOUT_MARKER" ]]` — the marker is `mktemp`-unique per invocation, eliminating PID-reuse false positives. Exit code 124 (GNU `timeout` convention) for external consumers; stderr sentinel `[CLAUDE-PRISM: soft-timeout at STAGE=exec after ${TIMEOUT_S}s]` for human-readable diagnosis
- **`SOFT_TIMEOUT` outcome in `scripts/analyze-log.sh`** — log-event-driven classification via `msg ~ /^soft_timeout /` match, prioritized over subsequent `ERROR` / `SIGNAL` events from the same pid (both of which `call-*.sh` also emits during teardown). Summary now shows `TO  Soft-timeout: N` alongside the existing `OK / ER / SG / !!` counters

### Security

- **Strict ISO-8601 timestamp validation in `analyze-log.sh:to_epoch`** (OWASP A03). The `awk` function previously interpolated `$ts` (first whitespace-delimited field of each matching log line) into a shell command via `cmd | getline`. Legitimate log entries produced by `_log` are always well-formed, but if the log file were externally tampered — e.g. by a local attacker with write access to `~/.claude/logs/`, or by a future log writer accepting user-controlled content in field `$1` — a crafted "timestamp" like `$(touch /tmp/pwned)` would execute. Added a strict regex gate (`^[0-9]{4}-...Z$`) before shell interpolation. Zero false negatives for legitimate entries; adversarial fixtures verified blocked

### Testing

- **Added Test 13** (6 regression cases) to `tests/smoke-test.sh` using injected fake CLI binaries via `CODEX_BIN` / `GEMINI_BIN` env vars — no real API calls, no credentials required. T13.1 codex normal completion (rc=0, no sentinel, and no `soft_timeout` event in log — the absence-assertion is the boundary-race regression guard); T13.2 codex timeout fires (rc=124 + sentinel + log event); T13.3 custom `CLAUDE_PRISM_TIMEOUT=5` honoured within ±2s tolerance; T13.4 no orphan `fake-slow-cli` processes after timeout fires (process-leak regression guard); T13.5 gemini mirror fires identically to codex (byte-sync contract verification); T13.6 overflow `CLAUDE_PRISM_TIMEOUT=9999999999` falls back to 110 with WARN log (macOS BSD `sleep` bypass regression guard). smoke-test total: 37 → 43

### Mechanism design (rationale in `.claude/pi-plans/soft-timeout-call-scripts.md`)

Three provider-proposed mechanisms were refuted by local POC during plan revision:
- **SIGALRM-to-parent trap does not interrupt foreground pipelines.** Bash queues the signal until the shell regains control, so `trap '...' ALRM` only fires after the pipeline completes naturally — timeout effectively useless. Verified on Bash 5.3.9 + 3.2.57. Fix: background the pipeline with `&` so `wait` is interruptible; use a watcher subshell instead of parent trap
- **rc=124 cannot drive analyzer classification** because `analyze-log.sh` doesn't inspect exit codes — it matches log message patterns. SOFT_TIMEOUT is therefore log-event-driven (cleaner — no cross-layer exit-code leak) while still exiting 124 for external consumers
- **Killing pipeline middle-stage via `$!` alone is insufficient.** `$!` captures the last pipeline member (`tee`), and SIGPIPE does not propagate to middle-stage CLIs that don't write stdout. `pkill -TERM -P $$` targets all parent's direct children, which includes every pipeline member

### Notes

- Mechanism B (Gemini service-side tail event → harness drops output silently) is NOT addressed by this change — that requires skill-layer log fallback, deferred
- Byte-sync between `call-codex.sh` and `call-gemini.sh` enforced by `Keep in sync` comment header; future CI lint check to be added (deferred, not v0.14.0 scope)

## v0.13.0 (2026-04-23)

**Skill layer hardening — sub-agent fan-out + `GEMINI_MODEL` passthrough.** Two related policy changes to the `pi-*` command surface, both prompted by bg-regression experiment data (N=36+ runs) showing the prior prescription did not deliver its stated guarantee.

### Changed

- **Sub-agent fan-out replaces main-conversation parallel Bash** for `pi-askall`, `pi-plan`, and `pi-multi-review`. Main-conversation Bash is a structural FIFO queue — the second parallel Bash waits for the first to finish (`delta ≈ first_exec` precisely, N=7 across two capacity slots). The v0.12.3 prescription "send two Bash tool calls in a single response" was therefore semantically a no-op: provider calls ran sequentially, not concurrently. v0.13.0 dispatches via two parallel `Agent` tool calls (`subagent_type: "general-purpose"`), each invoking its CLI wrapper inside the sub-agent's own Bash — sub-agent Bash dispatches in parallel (median delta 2.8s, N=13). Live POC captured during this release confirms the pattern works. This is primarily a correctness fix (restore parallel semantics); for long provider calls it also saves wall-clock (pi-plan baseline ~156s via fan-out vs ~218s hypothetical FIFO = 28% saved)
- **Skills no longer set `GEMINI_MODEL`** — the user's shell environment passes through to the sub-agent's Bash, then `call-gemini.sh`, then the Gemini CLI, with no skill-side override. Previously `pi-plan`, `pi-multi-review`, `pi-fact-check`, and `pi-research` all wrapped their Gemini call with `GEMINI_MODEL="${GEMINI_MODEL_DEEP:-${GEMINI_MODEL:-}}"`, which gave `GEMINI_MODEL_DEEP` priority over the user's explicit `GEMINI_MODEL` choice. The layering looked user-respectful but silently promoted the deep tier whenever `GEMINI_MODEL_DEEP` was set. If a call fails with `RATE_LIMIT` / capacity, the skill surfaces the error and leaves the tier decision to the user

### Documentation

- **Dispatch rules preamble** in `pi-askall`, `pi-plan`, and `pi-multi-review` replaces the v0.12.3 "Bash invocation rules" notice. Explains why main-conversation parallel Bash fails (FIFO), how sub-agent fan-out differs (separate dispatch layer), and when `run_in_background: true` still applies (unchanged escape hatch for genuinely-long calls)
- **`GEMINI_MODEL` passthrough note** in `pi-askall` spells out the policy so future skill authors don't reintroduce layering

### Breaking changes

- **`GEMINI_MODEL_DEEP` is no longer read** by any skill. Users who set `GEMINI_MODEL_DEEP` to force the deep tier for `pi-plan` / `pi-multi-review` / `pi-fact-check` / `pi-research` will, after upgrade, fall through to whatever `GEMINI_MODEL` is set to (or the CLI's own default if unset). **Migration**: if you previously set `GEMINI_MODEL_DEEP=gemini-3-pro-preview` to keep the deep tier for reviews while running Flash for general Q&A, either (a) set `GEMINI_MODEL=gemini-3-pro-preview` globally and accept the deep tier everywhere, (b) launch Claude Code with the env var set for that session only, e.g. `GEMINI_MODEL=gemini-3-pro-preview claude`, or (c) leave it unset and let the CLI default apply
- **Downstream skill authors** extending `pi-askall` / `pi-plan` / `pi-multi-review` verbatim must follow the new sub-agent fan-out pattern — the old "two parallel Bash tool calls" prescription is gone

### Notes

- For end-users who did NOT set `GEMINI_MODEL_DEEP`, the only behaviour change is "parallel now actually parallel"
- `pi-fact-check` and `pi-research` make one Gemini Bash call + N `WebSearch` calls. They don't trigger the two-Bash FIFO, so sub-agent fan-out is not applied there — only the `GEMINI_MODEL` passthrough change affects them. The Bash + WebSearch queue interaction is untested; a future investigation tied to the `call-*.sh` soft-timeout work may surface additional changes

## v0.12.6 (2026-04-20)

**Regression test hardening** — lock in the v0.12.3→v0.12.5 stdin fixes with six dedicated test cases so future edits to the stdin block in `call-codex.sh` / `call-gemini.sh` fail fast instead of silently regressing.

### Testing

- **Added six stdin regression scenarios** to `tests/smoke-test.sh` (pipe / file redirect / `</dev/null` × 2 wrappers). Uses exact prompt-length assertions so silent truncation or drop cannot pass the test — the prior `> 1` form would have accepted partial-byte loss. Inherited non-EOF fd case intentionally excluded and documented in-line (FIFO is not a valid proxy for the v0.12.3 anonymous-pipe bug shape, and macOS lacks `timeout`). smoke-test total: 31 → 37
- **Added `# Keep in sync with scripts/call-<other>.sh` comments** above the shared stdin block in both wrappers, aligning with the existing `install.sh` / `uninstall.sh` mirror convention so manual edits carry a visible sync signal

### Fixed

- **EXIT trap for temp dir cleanup in smoke-test.sh regression block** — the new Test 12 section created two temp dirs (`mktemp -d` for fixture + git repo) but relied on a trailing `rm -rf` for cleanup. Under `set -euo pipefail`, any error between `mktemp` and the final cleanup would leak the dirs (including an initialized git repo). Register an `EXIT` trap immediately after both `mktemp -d` calls so cleanup runs on success, error, and signal paths alike. OWASP A10 Mishandling of Exceptional Conditions

## v0.12.5 (2026-04-20)

**Hardening pass on top of v0.12.4** — adversarial review (Codex) and security lint surfaced two issues that complete the stdin attack surface fix.

### Fixed

- **Silent drop of `< file.txt` redirect input** — v0.12.4's stdin guard `[[ ! -t 0 && -p /dev/stdin ]]` correctly stopped the `cat` deadlock but narrowed too far: a regular-file redirect (`call-codex.sh "..." < diff.txt`) is not a FIFO under bash, so the redirected payload was discarded without warning. Broaden the guard to `[[ ! -t 0 && ( -p /dev/stdin || -f /dev/stdin ) ]]` so any finite EOF-reaching source is consumed; non-EOF inherited fds still skip (preserving the v0.12.4 fix). Verified across pipe / file redirect / `</dev/null` / no-redirect inheritance
- **Log injection via unsanitized CLI stderr** — `_log ERROR "... $err_text"` in both wrappers wrote raw subprocess stderr to `~/.claude/logs/multi-ai.log`, which lets a crafted prompt fragment echoed back by Codex/Gemini forge log entries (e.g. `\n2026-04-20T00:00:00Z [codex] [INFO] [pid=1] fake success`). The v0.12.4 stdin guard widening enlarged the attacker-controlled payload surface (file redirect now consumed too), so harden the sink. Strip newlines via `tr '\n' ' '` before the `_log` call. The user-facing `Details:` stderr echo keeps the raw text — that path is for terminal display, not structured log parsing. OWASP A09 Logging & Monitoring Failures

## v0.12.4 (2026-04-20)

**Fix stdin pipe deadlock** — `call-codex.sh` / `call-gemini.sh` no longer hang on `cat` when invoked without an upstream pipe.

### Fixed

- **stdin pipe deadlock when no pipe present** — `call-codex.sh` / `call-gemini.sh` previously hung on `cat` when invoked without a pipe but with an inherited non-TTY stdin (a Claude Code v0.12.3+ subshell behavior surfaced after the auto-background bypass landed). Affected 6 commands across 8 call sites: `pi-plan`, `pi-multi-review`, `pi-code-review` (main path), `pi-ui-design` (spec-generation step), `pi-ask-codex` (no-context path), and `pi-ask-gemini` (no-context path). The fix narrows the stdin guard from `[[ ! -t 0 ]]` to `[[ ! -t 0 && -p /dev/stdin ]]` so the script only reads when there's an actual FIFO with a writer that will close. The 8 pipe-based call sites (`pi-research`, `pi-askall`, `pi-fact-check`, `pi-ui-review`, `pi-ui-design` HTML generation, `pi-code-review` long-input mode, `pi-ask-{codex,gemini}` with-context path) are unaffected.

### Documentation

- **Added "Cache TTL Behavior" section** under Observability in both `README.md` and `README.zh-TW.md`. Documents Claude Code's current 5-minute prompt cache TTL (applying to all subscribers regardless of Pro or Max tier), the 2026-03-08 Claude Code-wide shift from a 1-hour default back to 5 minutes (see [GitHub issue #46829](https://github.com/anthropics/claude-code/issues/46829)), and clarifies that "Max subscribers automatically receive a 1-hour TTL" is an unverified community claim — Anthropic's official [prompt caching documentation](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) does not gate TTL by subscription tier. Non-alarmist informational framing; no preamble, command, or script changes
- **Sharpened review-insights wording** in both `README.md` and `README.zh-TW.md` to accurately reflect that Claude (the AI) participates in both writing and reading sides of the JSONL log: at write time Claude interprets Codex/Gemini output (emoji→severity mapping, source inference, ≥80 confidence filter) before appending; at read time `review-insights.sh` only computes raw counts via `jq`, with deeper interpretation (trends, root causes) handled by Claude. Replaced passive voice / "automatically records" phrasing across 4 spots — How It Works step 7, the Review Insights section, the bash comment annotation, and the Privacy "What Stays Local" note — so readers don't mistake the pipeline for pure script automation

## v0.12.3 (2026-04-18)

**Bypass Claude Code auto-background regression** — commands and scripts harden against the 2026-04+ regression where Claude Code's auto-background path silently kills child processes (output file stays 0 bytes, `ps` shows no trace).

### Root cause

Claude Code 2026-04+ versions (observed on v2.1.114) changed the auto-background lifecycle: when the runtime decides to background a Bash tool invocation, the child process gets killed instead of detached — the task dir gets a "running" entry but `ps aux` shows nothing, and output files stay empty because the process never reached the `tee` write. Explicit `run_in_background: true` uses a different (working) lifecycle, and foreground synchronous calls are unaffected.

### Mitigation

- **All 10 `pi-*` commands** now include a "Bash invocation rules" preamble directing Claude to call `call-codex.sh` / `call-gemini.sh` in **foreground synchronous mode** with an explicit `timeout: 600000` (10-minute ceiling). Explicit `&`, `run_in_background: true`, and `nohup` are forbidden — any path that lets Claude Code decide to background triggers the regression. `run_in_background: true` remains as an escape hatch for commands genuinely expected to exceed 10 minutes
- **Parallel provider calls** (`pi-askall`, `pi-multi-review`, `pi-plan`) achieve concurrency by sending two Bash tool calls in a single response, each foreground-synchronous, instead of relying on shell-level `&`

### Observability (new)

- **Lifecycle logging** — `call-codex.sh` and `call-gemini.sh` gain `INVOKE` (entry), `STAGE` (tracks `entry` → `parse_flags` → `stdin_read` → `git_check` → `binary_resolve` → `exec` → `done`), and `SIGNAL` (HUP/INT/TERM traps) log events. Every log line now carries a `[pid=N]` prefix to group events by invocation. `SIGKILL` is uncatchable, so the absence of a `SUCCESS`/`ERROR`/`SIGNAL` event after an `INVOKE` is the signature of an auto-background kill
- **SIGHUP trap replaces silent ignore** — the previous `trap '' HUP` is replaced with `trap '_log_signal HUP' HUP`. Behavior is unchanged (HUP still doesn't terminate the script), but now the event is recorded
- **`scripts/analyze-log.sh`** — new utility that reads `multi-ai.log`, groups entries by pid, and reports each invocation's outcome (Success / Error / Signal / Silent death). Silent deaths point to suspected Claude Code auto-background SIGKILLs. Pre-v0.12.3 log entries (no pid prefix) are skipped

### Documentation

- **Removed "Changing the output language" section** from both `README.md` and `README.zh-TW.md`. The original guidance had two problems: it biased the example toward a specific language (a public open-source package shouldn't assume its readers' preferred language), and it pointed users at `commands/*.md` files that `./install.sh` overwrites on every upgrade — so the customization wouldn't persist anyway. A proper mechanism (likely an env var) is deferred to a future release
- **Added "Invocation Diagnostics" section** under Observability in both README variants, documenting `analyze-log.sh` usage, the four outcome categories (SUCCESS / ERROR / SIGNAL / SILENT), and how SILENT deaths signal Claude Code auto-background SIGKILL events

## v0.12.2 (2026-04-11)

**Background fallback** — all 10 commands now recover from Bash tool backgrounding.

- **Fallback read instructions** — every `pi-*` command prompt now includes a fallback directive: if the Bash tool was backgrounded or returned empty output, Claude reads the result from `~/.claude/logs/pi-{codex,gemini}-last.out` (persisted by the script's `tee` safety net since v0.11.4/v0.12.0)
- Completes the three-layer defense against background output loss: script-level `tee` streaming (v0.11.4) → file persistence (v0.12.0) → command-level fallback read (v0.12.2)

## v0.12.1 (2026-04-07)

**Community** — added contributing guide and code of conduct.

- **CONTRIBUTING.md** — development setup, code standards (Bash 3.2+, ShellCheck), testing, commit convention, PR process, and contribution boundaries (what we accept / don't accept)
- **CODE_OF_CONDUCT.md** — Contributor Covenant 2.1
- **README updates** — added Contributor Covenant badge and Contributing section to both `README.md` and `README.zh-TW.md`

## v0.12.0 (2026-04-03)

**Adversarial review upgrade** — review prompts redesigned from neutral "Senior Reviewer" to adversarial stance with divided attack surfaces, inspired by codex-plugin-cc concepts (Apache 2.0).

### Adversarial review prompts

- **pi-code-review** — Codex prompt upgraded to adversarial stance: "break confidence in the change, not validate it." 9-category attack surface (auth, data loss, race conditions, rollback safety, edge cases, schema drift, observability, annotation compliance, guideline compliance), finding bar (every finding must answer what/why/impact/fix), calibration rules ("prefer one strong finding over several weak ones"), and final self-check
- **pi-multi-review** — both provider prompts upgraded to adversarial with **divided attack surfaces**: Codex attacks security & data integrity (7 categories), Gemini attacks design, UX & maintainability (7 categories). Aligns with existing domain-aware weighting (Codex → backend authority, Gemini → frontend authority)
- **Consistent filtering** — "DO NOT flag" criteria unified across all three prompts (including lint-ignore/noqa/@ts-ignore exclusion)

### Output persistence safety net

- **Last-run output files** — `call-codex.sh` and `call-gemini.sh` now persist output to `~/.claude/logs/pi-codex-last.out` and `pi-gemini-last.out` (fixed paths, not temp files). Files survive script exit as a fallback if stdout is lost during background execution
- Builds on v0.11.4's `tee` streaming fix — stdout remains the primary output channel; file persistence is the safety net

## v0.11.4 (2026-04-03)

**Fix: streaming CLI output to prevent background execution data loss**

### Streaming output

- **`RESULT=$(...)` → `tee` streaming** — `call-codex.sh` and `call-gemini.sh` no longer buffer the entire CLI response in a shell variable. Output now streams directly to stdout via `tee`, so callers that background the script (e.g. Claude Code Bash tool auto-backgrounding) can capture output in real time instead of seeing 0 bytes
- **SIGHUP survival** — added `trap '' HUP` to both wrapper scripts so they survive terminal detach when backgrounded, preventing silent process death
- **bash 3.2 compat (error path)** — `${err_text,,}` in installed scripts now uses `printf | tr` (matching the v0.11.3 repo fix that hadn't been re-installed)

## v0.11.3 (2026-03-29)

**Fix: macOS bash 3.2 compatibility** — error classification no longer breaks on stock macOS bash.

### Bash compatibility

- **`${var,,}` → `tr` replacement** — `call-codex.sh` and `call-gemini.sh` error classification used bash 4+ lowercase syntax (`${err_text,,}`), which causes `bad substitution` on macOS built-in bash 3.2. Replaced with POSIX-compatible `printf | tr '[:upper:]' '[:lower:]'`
- Only affects the error path (CLI call failure); normal execution was never impacted

## v0.11.2 (2026-03-29)

**Fix: pi-ui-review stdin pipe** — large code reviews no longer silently fail.

### Stdin pipe migration

- **`/pi-ui-review` stdin pipe** — code content moved from shell argument to stdin pipe, matching the v0.9.6 standard used by all other commands. Previously, large frontend code reviews caused `call-gemini.sh` to return 0 bytes silently due to ARG_MAX limits and shell metacharacter expansion in `run_in_background` mode
- **Historical review comments via stdin** — Step 1.7 PR comment context also routed through stdin to avoid argument overflow on repos with extensive review history

## v0.11.1 (2026-03-27)

**Model Tier Override** — two-tier model setup for heavy-reasoning commands.

### Model tier override

- **`GEMINI_MODEL_DEEP` env var** — new environment variable for selecting a higher-tier Gemini model on heavy-reasoning commands. Falls back to `GEMINI_MODEL`, then CLI default — zero behavioral change for existing setups
- **Four commands upgraded** — `/pi-fact-check`, `/pi-research`, `/pi-multi-review`, and `/pi-plan` now use `GEMINI_MODEL_DEEP` when set, automatically routing to Gemini Pro for deep reasoning while keeping Flash as the fast default for other commands
- **Nounset-safe** — parameter expansion uses `${GEMINI_MODEL_DEEP:-${GEMINI_MODEL:-}}` to avoid `set -u` breakage in strict shell environments

## v0.11.0 (2026-03-27)

**Provider Resilience** — dual-track research, structured error diagnostics, and graceful degradation across all commands.

Driven by Gemini CLI service degradation (Discussion [#22970](https://github.com/google-gemini/gemini-cli/discussions/22970): paid users hitting 429 errors, 7–10 min latency, 24hr+ outages post-March 25 update), this release hardens every command against provider instability.

### Dual-track research

- **`/pi-research` upgraded to dual-track** — now launches Gemini (search grounding) and WebSearch simultaneously, same architecture proven in `/pi-fact-check`. If Gemini times out or returns 429, WebSearch results cover the gap. Claude synthesizes all available sources with URL attribution
- **Source URLs in research reports** — Gemini prompted to return source URLs; WebSearch URLs included in final report. Claims without sources marked as (unverified)
- **Provider Status table** — research reports now begin with a track status table (Gemini ✅/⚠️, WebSearch ✅/⚠️, Claude ✅ always)

### Structured error diagnostics

- **Error classification in shell scripts** — `call-gemini.sh` and `call-codex.sh` now classify errors into 7 categories: `TIMEOUT`, `RATE_LIMIT`, `AUTH_ERROR`, `PERMISSION`, `SANDBOX` (Codex only), `NETWORK`, `CLI_ERROR`, plus `CLI_NOT_FOUND` for missing binaries
- **Bash regex over grep** — error classification uses `[[ "$err_lower" =~ pattern ]]` instead of `echo | grep -qi`, eliminating subshell forks on the error path and avoiding a `set -euo pipefail` edge case. Lowercase conversion updated to `printf | tr` for macOS bash 3.2 compatibility in v0.11.3
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
