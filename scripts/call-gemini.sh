#!/usr/bin/env bash
# call-gemini.sh — Gemini CLI wrapper for claude-prism
# Usage:
#   call-gemini.sh "your prompt"
#   echo "code" | call-gemini.sh "review this"
#   call-gemini.sh -m gemini-3-flash-preview "your prompt"
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
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [gemini] [$level] $*" >> "$LOG_FILE"
}

# --- Parse flags ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model) MODEL="$2"; shift 2 ;;
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
if [[ ! -t 0 ]]; then
    STDIN_DATA=$(cat)
    PROMPT="${PROMPT}

${STDIN_DATA}"
fi

_log INFO "model=${MODEL:-(default)} prompt_len=${#PROMPT} dry_run=$DRY_RUN"

# --- Dry run mode (no binary needed) ---
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Would call: gemini -p \"...\"${MODEL:+ -m $MODEL}"
    echo "[DRY RUN] Prompt length: ${#PROMPT} chars"
    _log INFO "dry run complete"
    exit 0
fi

# --- Resolve gemini binary ---
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
    echo "Error: gemini CLI not found. Install: npm install -g @google/gemini-cli" >&2
    exit 1
fi

# --- Execute ---
# Long prompts go via stdin to avoid ARG_MAX limits.
# -p " " activates headless mode; Gemini appends it to stdin (harmless).
CMD=("$GEMINI_BIN")
[[ -n "$MODEL" ]] && CMD+=(-m "$MODEL")

if [[ ${#PROMPT} -gt 4000 ]]; then
    RESULT=$(printf '%s' "$PROMPT" | "${CMD[@]}" -p " " 2>&1) || {
        rc=$?
        _log ERROR "gemini call failed (exit $rc): ${RESULT:0:200}"
        echo "$RESULT" >&2
        exit $rc
    }
else
    RESULT=$("${CMD[@]}" -p "$PROMPT" 2>&1) || {
        rc=$?
        _log ERROR "gemini call failed (exit $rc): ${RESULT:0:200}"
        echo "$RESULT" >&2
        exit $rc
    }
fi

_log INFO "success response_len=${#RESULT}"
echo "$RESULT"
