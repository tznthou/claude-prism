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

mkdir -p "$LOG_DIR"
ERR_TMP=$(mktemp)
OUT_TMP="${LOG_DIR}/pi-codex-last.out"

# --- Soft-timeout: wall-clock guard (v0.14.0+) ---
# Keep in sync with scripts/call-gemini.sh — any edit to the timeout block must mirror.
# Fires before the ~130s Claude Code harness watchdog so the script exits with a
# structured marker (sentinel + log event + rc=124) rather than silent SIGKILL.
# Mechanism: bg pipeline + watcher subshell + pkill -P parent. Validated on
# Bash 5.3.9 + Bash 3.2.57 (see .claude/pi-plans/soft-timeout-call-scripts.md).
TIMEOUT_S="${CLAUDE_PRISM_TIMEOUT:-110}"
if ! [[ "$TIMEOUT_S" =~ ^[1-9][0-9]*$ ]]; then
    _log WARN "invalid CLAUDE_PRISM_TIMEOUT=$TIMEOUT_S — falling back to 110"
    TIMEOUT_S=110
fi

printf '%s' "$PROMPT" | "${CMD[@]}" - 2>"$ERR_TMP" | tee "$OUT_TMP" &
LAST=$!

# Watcher: sleep T → emit log event → TERM all pipeline members (parent's direct
# children). Watcher kills itself via pkill -P $$; KILL escalation is in parent
# EXIT trap, not here.
(
    sleep "$TIMEOUT_S"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [codex] [WARN] [pid=$$] soft_timeout stage=exec elapsed_s=$TIMEOUT_S" >> "$LOG_FILE"
    pkill -TERM -P $$ 2>/dev/null || true
) &
WPID=$!

# EXIT trap: kill watcher + KILL-escalate any surviving pipeline members + rm ERR_TMP.
# SIGHUP still handled by _log_signal HUP trap (set earlier — preserves bg detach).
trap 'kill "$WPID" 2>/dev/null || true; pkill -KILL -P $$ 2>/dev/null || true; rm -f "$ERR_TMP"' EXIT

set +e
wait "$LAST" 2>/dev/null
rc=$?
set -e

# Soft-timeout classification: rc=143/137 + our log event = it's our timeout, not harness.
# pid-scoped grep avoids false match from prior invocations in shared log file.
if { [[ $rc -eq 143 ]] || [[ $rc -eq 137 ]]; } && grep -q "\[pid=$$\] soft_timeout" "$LOG_FILE"; then
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
