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
DRY_RUN=false
LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/multi-ai.log"

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
_log INFO "invoke ppid=$PPID stage=entry"

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
                read-only|sandbox|none) : ;;
                *) echo "Error: invalid sandbox mode '$2'. Valid: read-only, sandbox, none" >&2; exit 1 ;;
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

# --- Git repo check (before dry-run so --dry-run reflects actual sandbox) ---
# codex exec --sandbox read-only requires a git repo; if not in one,
# downgrade to "none" so pure Q&A calls (e.g. pi-askall) still work.
# Only downgrade "read-only" — if caller explicitly requested "sandbox",
# respect that intent and let codex fail with its own error.
STAGE="git_check"
if [[ "$SANDBOX" == "read-only" ]] && ! git rev-parse --is-inside-work-tree &>/dev/null; then
    _log WARN "not inside a git repo — downgrading sandbox from 'read-only' to 'none'"
    echo "Warning: not in a git repo — sandbox downgraded to 'none'" >&2
    SANDBOX="none"
fi

_log INFO "model=${MODEL:-(default)} sandbox=$SANDBOX prompt_len=${#PROMPT} dry_run=$DRY_RUN"

# --- Dry run mode (no binary or git repo needed) ---
STAGE="dry_run"
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Would call: codex exec${MODEL:+ --model $MODEL} --sandbox $SANDBOX \"...\""
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

printf '%s' "$PROMPT" | "${CMD[@]}" - 2>"$ERR_TMP" | tee "$OUT_TMP" &
LAST=$!

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

# EXIT trap: kill watcher + KILL-escalate any surviving pipeline members + clean temp files.
# SIGHUP still handled by _log_signal HUP trap (set earlier — preserves bg detach).
# DO NOT rm "$OUT_TMP" here — skill fallback reads it after this wrapper exits (v0.14.2 contract).
trap 'kill "$WPID" 2>/dev/null || true; pkill -KILL -P $$ 2>/dev/null || true; rm -f "$ERR_TMP" "$TIMEOUT_MARKER"' EXIT

set +e
wait "$LAST" 2>/dev/null
rc=$?
set -e

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
if { [[ $rc -eq 143 ]] || [[ $rc -eq 137 ]]; } && [[ -s "$TIMEOUT_MARKER" ]]; then
    echo "[CLAUDE-PRISM: soft-timeout at STAGE=exec after ${TIMEOUT_S}s]" >&2
    _log ERROR "soft_timeout killed codex CLI after ${TIMEOUT_S}s"
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
        diag="SANDBOX: Codex sandbox restriction. Try --sandbox none for Q&A."
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
_log INFO "success response_len=$(wc -c < "$OUT_TMP" | tr -d ' ')"
