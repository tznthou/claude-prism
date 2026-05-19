#!/usr/bin/env bash
# call-codex.sh — Codex CLI wrapper for claude-prism
# Usage:
#   call-codex.sh "your prompt"
#   echo "code" | call-codex.sh "review this"
#   call-codex.sh -m model-name "your prompt"
#   call-codex.sh --dry-run "your prompt"   # test without calling API

set -euo pipefail

MODEL="${CODEX_MODEL:-}"
SANDBOX="read-only"
SKIP_GIT_CHECK=false
DRY_RUN=false
LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
mkdir -p "$LOG_DIR"

# --- Log rotation (Phase B, v0.14.4+) ---
# Monthly rotation: actual file is multi-ai-YYYY-MM.log; multi-ai.log is a
# symlink to the current month so analyze-log.sh / usage-summary.sh / external
# greppers see "latest view" transparently. Historical query: grep across
# multi-ai-*.log glob. Keep in sync with scripts/call-gemini.sh.
LOG_FILE="$LOG_DIR/multi-ai-$(date -u +%Y-%m).log"
LOG_LATEST="$LOG_DIR/multi-ai.log"
# One-time migration: pre-rotation regular file → archive (mv -n is BSD-safe;
# concurrent wrappers race-losing see no-op since source already moved).
if [[ -e "$LOG_LATEST" && ! -L "$LOG_LATEST" ]]; then
    mv -n "$LOG_LATEST" "$LOG_DIR/multi-ai-archive-pre-rotation.log" 2>/dev/null || true
fi
# Maintain "latest" symlink to current month (ln -sf is POSIX atomic on rename).
ln -sf "$(basename "$LOG_FILE")" "$LOG_LATEST" 2>/dev/null || true

# --- Observability capture (Phase A1, v0.14.4+) ---
# Captured early so invoke line + heartbeat + end lines all reference same values.
# Keep in sync with scripts/call-gemini.sh.
# CWD: tr strips \n and " to prevent log line splitting / quote escape (OWASP A09).
# CC_VER: AI_AGENT env-var is set by Claude Code harness; fallback "unknown" outside CC.
# CALLER: optional env-var set by skill template (direct / sub-agent / manual).
START_TS=$(date +%s)
MAIN_PID=$$
CALLER="${CLAUDE_PRISM_CALLER:-unknown}"
CWD=$(pwd | tr -d '\n"')
CC_VER="${AI_AGENT:-unknown}"

# --- Logging ---
_log() {
    local level="$1"; shift
    mkdir -p "$LOG_DIR"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [codex] [$level] [pid=$$] $*" >> "$LOG_FILE"
}

# --- Lifecycle observability (v0.12.3+) ---
# Distinguish "not invoked" from "invoked then SIGKILL'd" when diagnosing
# Claude Code 2026-04+ auto-background regressions (child gets killed,
# output file stays 0 bytes, ps shows no trace). SIGKILL is uncatchable —
# absence of SUCCESS/ERROR/SIGNAL after INVOKE = likely SIGKILL.
STAGE="entry"
_log_signal() {
    _log WARN "signal SIG$1 stage=$STAGE"
}
trap '_log_signal HUP' HUP
trap '_log_signal INT; exit 130' INT
trap '_log_signal TERM; exit 143' TERM
_log INFO "invoke ppid=$PPID stage=entry caller=\"$CALLER\" cwd=\"$CWD\" cc_ver=\"$CC_VER\""

# --- Parse flags ---
STAGE="parse_flags"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model)
            [[ $# -ge 2 ]] || { echo "Error: -m requires a model name" >&2; exit 1; }
            MODEL="$2"; shift 2 ;;
        --sandbox)
            [[ $# -ge 2 ]] || { echo "Error: --sandbox requires a mode" >&2; exit 1; }
            case "$2" in
                read-only|workspace-write|danger-full-access) : ;;
                *) echo "Error: invalid sandbox mode '$2'. Valid: read-only, workspace-write, danger-full-access" >&2; exit 1 ;;
            esac
            SANDBOX="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true; shift ;;
        *) break ;;
    esac
done

PROMPT="${1:-}"

if [[ -z "$PROMPT" ]]; then
    echo "Usage: call-codex.sh [-m model] [--sandbox mode] [--dry-run] \"prompt\"" >&2
    exit 1
fi

# --- Append stdin if available ---
# Keep in sync with scripts/call-gemini.sh — any edit to the stdin block must mirror.
# Only read stdin when it's an actual pipe or regular file — i.e. a source that
# will reach EOF. `! -t 0` alone deadlocks `cat` when Claude Code v0.12.3+
# subshells pass through a non-TTY stdin that never closes; allowing -f as well
# preserves `call-codex.sh "..." < file.txt` redirect usage without silent drop.
STAGE="stdin_read"
if [[ ! -t 0 && ( -p /dev/stdin || -f /dev/stdin ) ]]; then
    STDIN_DATA=$(cat)
    PROMPT="${PROMPT}

${STDIN_DATA}"
fi

# --- Git repo check (before dry-run so --dry-run reflects actual command) ---
# codex 0.130.0+ enforces a "trusted directory" check independent of sandbox mode:
# any sandbox value (read-only/workspace-write/danger-full-access) refuses to run
# outside a git repo unless --skip-git-repo-check is passed. Keep sandbox=read-only
# (preserves Q&A intent: no writes) and add the flag so pi-askall etc. still work
# when invoked from non-repo cwds like /tmp.
STAGE="git_check"
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    _log WARN "not inside a git repo — passing --skip-git-repo-check"
    echo "Warning: not in a git repo — using --skip-git-repo-check" >&2
    SKIP_GIT_CHECK=true
fi

_log INFO "model=${MODEL:-(default)} sandbox=$SANDBOX skip_git_check=$SKIP_GIT_CHECK prompt_len=${#PROMPT} dry_run=$DRY_RUN"

# --- Dry run mode (no binary or git repo needed) ---
STAGE="dry_run"
if [[ "$DRY_RUN" == true ]]; then
    SKIP_FLAG=""
    [[ "$SKIP_GIT_CHECK" == true ]] && SKIP_FLAG=" --skip-git-repo-check"
    echo "[DRY RUN] Would call: codex exec${MODEL:+ --model $MODEL} --sandbox $SANDBOX${SKIP_FLAG} \"...\""
    echo "[DRY RUN] Prompt length: ${#PROMPT} chars"
    _log INFO "dry run complete"
    exit 0
fi

# --- Resolve codex binary ---
STAGE="binary_resolve"
CODEX_BIN="${CODEX_BIN:-}"
if [[ -z "$CODEX_BIN" ]]; then
    for candidate in \
        "$HOME/.npm-global/bin/codex" \
        "$(command -v codex 2>/dev/null || true)" \
        "/usr/local/bin/codex"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            CODEX_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$CODEX_BIN" ]]; then
    _log ERROR "codex CLI not found"
    echo "Error: CLI_NOT_FOUND: Codex CLI not installed. Install: npm install -g @openai/codex" >&2
    exit 1
fi

# --- Execute ---
# Always pipe prompt via stdin to avoid exposing content in `ps` output.
# Stream directly to stdout (no buffering) so callers that background this
# script can still capture output in real time.
STAGE="exec"
CMD=("$CODEX_BIN" exec --sandbox "$SANDBOX")
[[ "$SKIP_GIT_CHECK" == true ]] && CMD+=(--skip-git-repo-check)
[[ -n "$MODEL" ]] && CMD+=(--model "$MODEL")

ERR_TMP=$(mktemp)
# Per-invocation OUT_TMP (v0.14.2+): prevents concurrent-tee interleaving when two
# sub-agents / sessions invoke this wrapper simultaneously. Symlink updated post-wait
# below. Keep in sync with scripts/call-gemini.sh — mktemp + symlink block mirrors.
# BSD mktemp requires XXXXXX at end of template (pattern verified at TIMEOUT_MARKER).
# Phase 2 (v0.14.3+): CLAUDE_PRISM_OUT_TMP env-var lets caller (skill layer) own
# the path — eliminates cross-session same-provider fallback wrong-file selection
# on shared symlink. When unset, falls back to v0.14.2 legacy (mktemp in LOG_DIR).
OUT_TMP="${CLAUDE_PRISM_OUT_TMP:-$(mktemp "${LOG_DIR}/pi-codex-last-XXXXXX")}"

# --- Soft-timeout: wall-clock guard (v0.14.0+) ---
# Keep in sync with scripts/call-gemini.sh — any edit to the timeout block must mirror.
# Fires before the ~130s Claude Code harness watchdog so the script exits with a
# structured marker (sentinel + log event + rc=124) rather than silent SIGKILL.
# Mechanism: bg pipeline + watcher subshell + pkill -P parent + per-invocation
# marker file for unambiguous classification. Validated on Bash 5.3.9 + Bash 3.2.57
# (see .claude/pi-plans/soft-timeout-call-scripts.md).
TIMEOUT_S="${CLAUDE_PRISM_TIMEOUT:-110}"
# Upper bound 3600 (1h) prevents values that `sleep` rejects. On macOS BSD sleep,
# `sleep 9999999999` exits immediately with usage error, which under `set -e` in
# the watcher subshell kills the watcher before it can log or pkill — silently
# disabling the timeout guard entirely (the exact regression this change prevents).
if ! [[ "$TIMEOUT_S" =~ ^[1-9][0-9]*$ ]] || (( TIMEOUT_S > 3600 )); then
    _log WARN "invalid CLAUDE_PRISM_TIMEOUT=$TIMEOUT_S (must be integer 1..3600) — falling back to 110"
    TIMEOUT_S=110
fi

# Per-invocation marker: solves PID reuse false positives. mktemp guarantees
# uniqueness; watcher writes non-empty content only when it actually fires, so
# parent can distinguish "we timed out" from "some prior pid=$$ invocation timed out".
TIMEOUT_MARKER=$(mktemp "${TMPDIR:-/tmp}/claude-prism-timeout.XXXXXX")

# --- First-byte detector marker (Phase A2 tri-state, v0.14.6+) ---
# Per-invocation marker; detector subshell writes unix-ts on first non-empty
# OUT_TMP observation; main shell reads after wait. Keep in sync with call-gemini.sh.
FIRST_BYTE_MARKER=$(mktemp "${TMPDIR:-/tmp}/claude-prism-first-byte.XXXXXX")

# --- Stale-content defense (Phase A2 tri-state, v0.14.6+) ---
# tee opens OUT_TMP with O_TRUNC but lazily (after fork+exec). The detector
# subshell starts in parallel and may observe stale bytes from a pre-existing
# CLAUDE_PRISM_OUT_TMP (Phase 2 caller-owned path), falsely classifying a
# pure stall as method=measured with near-zero ms while output_bytes=0.
# Synchronously truncate regular files before the pipeline+detector race;
# skip non-regular (FIFO/socket) — `-f` guards elsewhere already reject
# those paths. Keep in sync with call-gemini.sh.
if [ -f "$OUT_TMP" ]; then
    : > "$OUT_TMP" 2>/dev/null || true
fi

printf '%s' "$PROMPT" | "${CMD[@]}" - 2>"$ERR_TMP" | tee "$OUT_TMP" &
LAST=$!

# --- First-byte detector subshell (Phase A2 tri-state, v0.14.6+) ---
# Polls OUT_TMP at 1s; writes ts and exits when [[ -s ]] OR when pipeline dies.
# Second-precision (BSD date no %N); ms-precision upgrade deferred (Phase A3 skipped 5/10).
# `-s` cheaper than wc -c (boolean check). Keep in sync with call-gemini.sh.
FIRST_BYTE_POLL_S=1
(
    while :; do
        if [[ -f "$OUT_TMP" && -s "$OUT_TMP" ]]; then
            date +%s > "$FIRST_BYTE_MARKER"
            exit 0
        fi
        kill -0 "$LAST" 2>/dev/null || exit 0
        sleep "$FIRST_BYTE_POLL_S"
    done
) &
FBPID=$!

# --- Heartbeat subshell (Phase A1, v0.14.4+) ---
# Writes [DEBUG] alive line every 30s while pipeline runs. Two purposes:
#   1. Forensic timeline — bytes count per heartbeat reveals stall onset
#      (e.g. bytes stuck at N for 60s = upstream stalled at second 30).
#   2. Silent-kill death-time estimate — if Claude Code SIGKILLs wrapper,
#      last heartbeat ≈ death moment (SIGKILL is uncatchable, no exit log).
# DEBUG level: grep -E '\[(INFO|WARN|ERROR)\]' filters these out for daily monitoring;
# use `grep pid=N` for forensic full timeline. Keep in sync with scripts/call-gemini.sh.
HEARTBEAT_INTERVAL_S=30
(
    while sleep "$HEARTBEAT_INTERVAL_S"; do
        kill -0 "$LAST" 2>/dev/null || break
        bytes=$([ -f "$OUT_TMP" ] && wc -c < "$OUT_TMP" 2>/dev/null | tr -d ' \n' || echo 0)
        elapsed=$(($(date +%s) - START_TS))
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [codex] [DEBUG] [pid=$MAIN_PID] alive elapsed_s=$elapsed bytes=$bytes" >> "$LOG_FILE"
    done
) &
HBPID=$!

# Watcher: after sleep T, verify pipeline is still alive before firing.
# `kill -0` gate avoids boundary race where pipeline completes during sleep —
# without it, a natural-success run could still leave soft_timeout in the log.
# Order inside the gate: marker → log → pkill (so classification has truth even
# if pkill is a no-op on already-dead pipeline).
(
    sleep "$TIMEOUT_S"
    if kill -0 "$LAST" 2>/dev/null; then
        echo "$TIMEOUT_S" > "$TIMEOUT_MARKER"
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [codex] [WARN] [pid=$$] soft_timeout stage=exec elapsed_s=$TIMEOUT_S" >> "$LOG_FILE"
        pkill -TERM -P $$ 2>/dev/null || true
    fi
) &
WPID=$!

# EXIT trap: kill watcher + heartbeat + first-byte detector + KILL-escalate any
# surviving pipeline members + clean temp files (incl. first-byte marker).
# SIGHUP still handled by _log_signal HUP trap (set earlier — preserves bg detach).
# DO NOT rm "$OUT_TMP" here — skill fallback reads it after this wrapper exits (v0.14.2 contract).
trap 'kill "$WPID" "$HBPID" "$FBPID" 2>/dev/null || true; pkill -KILL -P $$ 2>/dev/null || true; rm -f "$ERR_TMP" "$TIMEOUT_MARKER" "$FIRST_BYTE_MARKER"' EXIT

# --- First-byte timestamp helper (Phase A2 tri-state, v0.14.6+) ---
# Sets FIRST_BYTE_MS and FIRST_BYTE_METHOD as globals (three states):
#   measured: detector observed first byte, marker has valid unix-ts
#   fallback: marker empty but OUT_TMP non-empty (race / fast-path);
#             ms value is wait-LAST exit time, NOT first-byte arrival.
#   na:       marker empty and OUT_TMP empty (pure stall / Mode A)
# Downstream consumers MUST filter on method=measured before using ms
# as latency. `tr -d ' \n'` + `^[0-9]+$` validate marker content (OWASP A09).
# Keep in sync with call-gemini.sh.
_first_byte_meta() {
    local ts delta elapsed_now
    if [[ -s "$FIRST_BYTE_MARKER" ]]; then
        ts=$(tr -d ' \n' < "$FIRST_BYTE_MARKER" 2>/dev/null || printf '')
        if [[ "$ts" =~ ^[0-9]+$ ]]; then
            delta=$((ts - START_TS))
            (( delta < 0 )) && delta=0
            FIRST_BYTE_MS="$((delta * 1000))"
            FIRST_BYTE_METHOD="measured"
            return 0
        fi
    fi
    if [[ -f "$OUT_TMP" && -s "$OUT_TMP" ]]; then
        elapsed_now=$(($(date +%s) - START_TS))
        (( elapsed_now < 0 )) && elapsed_now=0
        FIRST_BYTE_MS="$((elapsed_now * 1000))"
        FIRST_BYTE_METHOD="fallback"
        return 0
    fi
    FIRST_BYTE_MS="NA"
    FIRST_BYTE_METHOD="na"
}

set +e
wait "$LAST" 2>/dev/null
rc=$?
set -e

# Reap first-byte detector only when already completed (avoid block on no-output paths).
# Capture FIRST_BYTE_MS + FIRST_BYTE_METHOD globals; used by both success and
# soft_timeout end-log paths. Keep in sync with call-gemini.sh.
if [[ -s "$FIRST_BYTE_MARKER" ]]; then
    wait "$FBPID" 2>/dev/null || true
fi
FIRST_BYTE_MS=""
FIRST_BYTE_METHOD=""
_first_byte_meta

# Atomic symlink update (v0.14.2+): "pi-codex-last.out" points to this invocation's
# OUT_TMP. Runs after wait so OUT_TMP is fully written. Not conditioned on rc —
# partial output from soft-timeout or error paths stays readable by skill diagnostics.
# Concurrent invocations each own their mktemp file; last ln -sf wins the symlink,
# matching "latest" semantics of the fallback. Keep in sync with scripts/call-gemini.sh.
# `|| true`: symlink is best-effort observability; its failure must NOT mask the
# soft-timeout rc=143/137 classification that runs below (otherwise set -e exits
# with ln's rc and skill layer can't tell "timed out" from "CLI error").
# Phase 2 (v0.14.3+): legacy mode only. Env-var callers own $CLAUDE_PRISM_OUT_TMP
# path (may be outside LOG_DIR, where basename-relative symlink would dangle);
# they read their own OUT_TMP directly and don't need shared symlink.
if [ -z "${CLAUDE_PRISM_OUT_TMP:-}" ]; then
    ln -sf "$(basename "$OUT_TMP")" "${LOG_DIR}/pi-codex-last.out" || true
fi

# Soft-timeout classification: rc=143/137 + non-empty marker = our watcher fired.
# Marker is per-invocation (mktemp), eliminating PID-reuse false positives that
# would occur if we grepped the shared log file by pid alone.
# output_bytes: 0 = upstream stall (no byte before kill); >0 = slow but progressing.
# `-f` guard rejects FIFO / device / symlink-to-blocking-source paths (Phase 2 env-var
# caller may supply non-regular file; wc would read-block indefinitely → re-hang).
# Keep in sync with scripts/call-gemini.sh.
if { [[ $rc -eq 143 ]] || [[ $rc -eq 137 ]]; } && [[ -s "$TIMEOUT_MARKER" ]]; then
    # tr strips space AND newline: BSD wc may emit leading \n; unsanitized newline
    # in $out_bytes would split the log line (OWASP A09 Log Injection — same vector
    # err_text_safe defends below).
    out_bytes=$([ -f "$OUT_TMP" ] && wc -c < "$OUT_TMP" 2>/dev/null | tr -d ' \n' || echo 0)
    echo "[CLAUDE-PRISM: soft-timeout at STAGE=exec after ${TIMEOUT_S}s]" >&2
    _log ERROR "soft_timeout killed codex CLI after ${TIMEOUT_S}s output_bytes=$out_bytes first_byte_ms=$FIRST_BYTE_MS first_byte_method=$FIRST_BYTE_METHOD"
    exit 124
fi

if [[ $rc -ne 0 ]]; then
    err_text=$(cat "$ERR_TMP")
    # Classify the error for better diagnostics
    err_lower=$(printf '%s' "$err_text" | tr '[:upper:]' '[:lower:]')
    if [[ $rc -eq 137 || $rc -eq 143 ]]; then
        diag="TIMEOUT: Codex CLI was killed (signal $((rc - 128))). Likely capacity issue."
    elif [[ "$err_lower" =~ 429|rate.limit|quota|capacity ]]; then
        diag="RATE_LIMIT: Codex returned 429/quota error. Try again later."
    elif [[ "$err_lower" =~ sandbox|permission.denied|eperm ]]; then
        diag="SANDBOX: Codex sandbox restriction. Try --sandbox workspace-write for Q&A."
    elif [[ "$err_lower" =~ auth|token|api.key|credential|403 ]]; then
        diag="AUTH_ERROR: Codex authentication failed. Check OPENAI_API_KEY."
    elif [[ "$err_lower" =~ network|connect|econnrefused|etimedout|dns ]]; then
        diag="NETWORK: Cannot reach OpenAI API. Check internet connection."
    else
        diag="CLI_ERROR: Codex CLI exited with code $rc."
    fi
    # Strip newlines from $err_text before logging — CLI stderr can echo
    # prompt fragments that, if injected with "\n[INFO] [pid=N] ..." tokens,
    # would forge log entries (OWASP A09 Log Injection).
    err_text_safe=$(printf '%s' "$err_text" | tr '\n' ' ')
    _log ERROR "codex call failed ($diag): $err_text_safe"
    echo "Error: $diag" >&2
    [[ -n "$err_text" ]] && echo "Details: $err_text" >&2
    exit $rc
fi

STAGE="done"
_log INFO "success response_len=$(wc -c < "$OUT_TMP" | tr -d ' ') elapsed_s=$(($(date +%s) - START_TS)) first_byte_ms=$FIRST_BYTE_MS first_byte_method=$FIRST_BYTE_METHOD"
