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
if [[ ! -t 0 ]]; then
    STDIN_DATA=$(cat)
    PROMPT="${PROMPT}

${STDIN_DATA}"
fi

# --- Git repo check (before dry-run so --dry-run reflects actual sandbox) ---
# codex exec --sandbox read-only requires a git repo; if not in one,
# downgrade to "none" so pure Q&A calls (e.g. pi-askall) still work.
# Only downgrade "read-only" — if caller explicitly requested "sandbox",
# respect that intent and let codex fail with its own error.
if [[ "$SANDBOX" == "read-only" ]] && ! git rev-parse --is-inside-work-tree &>/dev/null; then
    _log WARN "not inside a git repo — downgrading sandbox from 'read-only' to 'none'"
    echo "Warning: not in a git repo — sandbox downgraded to 'none'" >&2
    SANDBOX="none"
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
    echo "Error: CLI_NOT_FOUND: Codex CLI not installed. Install: npm install -g @openai/codex" >&2
    exit 1
fi

# --- Execute ---
# Always pipe prompt via stdin to avoid exposing content in `ps` output.
# Stream directly to stdout (no buffering) so callers that background this
# script can still capture output in real time.
CMD=("$CODEX_BIN" exec --sandbox "$SANDBOX")
[[ -n "$MODEL" ]] && CMD+=(--model "$MODEL")

LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR"
ERR_TMP=$(mktemp)
OUT_TMP="${LOG_DIR}/pi-codex-last.out"
trap 'rm -f "$ERR_TMP"' EXIT  # Keep OUT_TMP as last-run safety net
trap '' HUP  # Survive background detach (SIGHUP)

printf '%s' "$PROMPT" | "${CMD[@]}" - 2>"$ERR_TMP" | tee "$OUT_TMP" || {
    rc=$?
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
    _log ERROR "codex call failed ($diag): $err_text"
    echo "Error: $diag" >&2
    [[ -n "$err_text" ]] && echo "Details: $err_text" >&2
    exit $rc
}

_log INFO "success response_len=$(wc -c < "$OUT_TMP" | tr -d ' ')"
