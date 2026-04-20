#!/usr/bin/env bash
# call-gemini.sh — Gemini CLI wrapper for claude-prism
# Usage:
#   call-gemini.sh "your prompt"
#   echo "code" | call-gemini.sh "review this"
#   call-gemini.sh -m model-name "your prompt"
#   call-gemini.sh --dry-run "your prompt"   # test without calling API

set -euo pipefail

MODEL="${GEMINI_MODEL:-}"
DRY_RUN=false
LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/multi-ai.log"

# --- Logging ---
_log() {
    local level="$1"; shift
    mkdir -p "$LOG_DIR"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [gemini] [$level] [pid=$$] $*" >> "$LOG_FILE"
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
        --dry-run)  DRY_RUN=true; shift ;;
        *) break ;;
    esac
done

PROMPT="${1:-}"

if [[ -z "$PROMPT" ]]; then
    echo "Usage: call-gemini.sh [-m model] [--dry-run] \"prompt\"" >&2
    exit 1
fi

# --- Append stdin if available ---
# Require -p /dev/stdin so we only consume an actual FIFO (pipe with a writer
# that will close). `! -t 0` alone deadlocks `cat` when Claude Code v0.12.3+
# subshells inherit a non-TTY stdin that never reaches EOF.
STAGE="stdin_read"
if [[ ! -t 0 && -p /dev/stdin ]]; then
    STDIN_DATA=$(cat)
    PROMPT="${PROMPT}

${STDIN_DATA}"
fi

_log INFO "model=${MODEL:-(default)} prompt_len=${#PROMPT} dry_run=$DRY_RUN"

# --- Dry run mode (no binary needed) ---
STAGE="dry_run"
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Would call: gemini -p \"...\"${MODEL:+ -m $MODEL}"
    echo "[DRY RUN] Prompt length: ${#PROMPT} chars"
    _log INFO "dry run complete"
    exit 0
fi

# --- Resolve gemini binary ---
STAGE="binary_resolve"
GEMINI_BIN="${GEMINI_BIN:-}"
if [[ -z "$GEMINI_BIN" ]]; then
    for candidate in \
        "$HOME/.npm-global/bin/gemini" \
        "$(command -v gemini 2>/dev/null || true)" \
        "/usr/local/bin/gemini"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            GEMINI_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$GEMINI_BIN" ]]; then
    _log ERROR "gemini CLI not found"
    echo "Error: CLI_NOT_FOUND: Gemini CLI not installed. Install: npm install -g @google/gemini-cli" >&2
    exit 1
fi

# --- Execute ---
# Always pipe prompt via stdin to avoid exposing content in `ps` output.
# Stream directly to stdout (no buffering) so callers that background this
# script can still capture output in real time.
# -p " " activates headless mode; Gemini appends it to stdin (harmless).
STAGE="exec"
CMD=("$GEMINI_BIN")
[[ -n "$MODEL" ]] && CMD+=(-m "$MODEL")

LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR"
ERR_TMP=$(mktemp)
OUT_TMP="${LOG_DIR}/pi-gemini-last.out"
trap 'rm -f "$ERR_TMP"' EXIT  # Keep OUT_TMP as last-run safety net
# SIGHUP handled by _log_signal HUP trap above (log + continue) — preserves
# background detach survival without silencing the signal.

printf '%s' "$PROMPT" | "${CMD[@]}" -p " " 2>"$ERR_TMP" | tee "$OUT_TMP" || {
    rc=$?
    err_text=$(cat "$ERR_TMP")
    # Classify the error for better diagnostics
    err_lower=$(printf '%s' "$err_text" | tr '[:upper:]' '[:lower:]')
    if [[ $rc -eq 137 || $rc -eq 143 ]]; then
        diag="TIMEOUT: Gemini CLI was killed (signal $((rc - 128))). Likely capacity issue or search grounding delay."
    elif [[ "$err_lower" =~ 429|rate.limit|quota|capacity ]]; then
        diag="RATE_LIMIT: Gemini returned 429/quota error. Try again later or use an API key (GEMINI_API_KEY)."
    elif [[ "$err_lower" =~ permission.denied|eperm ]]; then
        diag="PERMISSION: Filesystem permission denied. Check temp directory and file permissions."
    elif [[ "$err_lower" =~ auth|oauth|token|credential|403 ]]; then
        diag="AUTH_ERROR: Gemini authentication failed. Check OAuth session or API key."
    elif [[ "$err_lower" =~ network|connect|econnrefused|etimedout|dns ]]; then
        diag="NETWORK: Cannot reach Gemini API. Check internet connection."
    else
        diag="CLI_ERROR: Gemini CLI exited with code $rc."
    fi
    _log ERROR "gemini call failed ($diag): $err_text"
    echo "Error: $diag" >&2
    [[ -n "$err_text" ]] && echo "Details: $err_text" >&2
    exit $rc
}

STAGE="done"
_log INFO "success response_len=$(wc -c < "$OUT_TMP" | tr -d ' ')"
