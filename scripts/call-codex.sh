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
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [codex] [$level] $*" >> "$LOG_FILE"
}

# --- Parse flags ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model)   MODEL="$2"; shift 2 ;;
        --sandbox)    SANDBOX="$2"; shift 2 ;;
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
if [[ ! -t 0 ]]; then
    STDIN_DATA=$(cat)
    PROMPT="${PROMPT}

${STDIN_DATA}"
fi

_log INFO "model=${MODEL:-(default)} sandbox=$SANDBOX prompt_len=${#PROMPT} dry_run=$DRY_RUN"

# --- Dry run mode (no binary or git repo needed) ---
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Would call: codex exec${MODEL:+ --model $MODEL} --sandbox $SANDBOX \"...\""
    echo "[DRY RUN] Prompt length: ${#PROMPT} chars"
    _log INFO "dry run complete"
    exit 0
fi

# --- Resolve codex binary ---
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
    echo "Error: codex CLI not found. Install: npm install -g @openai/codex" >&2
    exit 1
fi

# --- Git repo check ---
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    _log ERROR "not inside a git repo"
    echo "Error: codex exec requires a git repo. cd into one first." >&2
    exit 1
fi

# --- Execute ---
# Long prompts go via stdin to avoid ARG_MAX limits.
CMD=("$CODEX_BIN" exec --sandbox "$SANDBOX")
[[ -n "$MODEL" ]] && CMD+=(--model "$MODEL")

if [[ ${#PROMPT} -gt 4000 ]]; then
    RESULT=$(printf '%s' "$PROMPT" | "${CMD[@]}" - 2>&1) || {
        rc=$?
        _log ERROR "codex call failed (exit $rc): ${RESULT:0:200}"
        echo "$RESULT" >&2
        exit $rc
    }
else
    RESULT=$("${CMD[@]}" "$PROMPT" 2>&1) || {
        rc=$?
        _log ERROR "codex call failed (exit $rc): ${RESULT:0:200}"
        echo "$RESULT" >&2
        exit $rc
    }
fi

_log INFO "success response_len=${#RESULT}"
echo "$RESULT"
