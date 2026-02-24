#!/usr/bin/env bash
# usage-summary.sh — Summarize multi-ai usage from logs
# Usage:
#   usage-summary.sh              # today's usage
#   usage-summary.sh --week       # last 7 days
#   usage-summary.sh --all        # all time
#   usage-summary.sh --date 2026-02-24  # specific date

set -euo pipefail

LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/multi-ai.log"

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

# --- Parse args ---
RANGE="today"
FILTER_DATE=""

case "${1:-}" in
    --week)   RANGE="week" ;;
    --all)    RANGE="all" ;;
    --date)
        [[ $# -ge 2 ]] || { echo "Error: --date requires YYYY-MM-DD" >&2; exit 1; }
        FILTER_DATE="$2"
        RANGE="date"
        ;;
    "")       RANGE="today" ;;
    *)        echo "Usage: usage-summary.sh [--week|--all|--date YYYY-MM-DD]" >&2; exit 1 ;;
esac

if [[ ! -f "$LOG_FILE" ]]; then
    echo "No log file found at $LOG_FILE"
    echo "Run some commands first (/ask-codex, /ask-gemini, /multi-review, etc.)"
    exit 0
fi

# --- Build date filter ---
case "$RANGE" in
    today)
        DATE_PREFIX=$(date -u +%Y-%m-%d)
        LABEL="Today ($DATE_PREFIX)"
        ;;
    week)
        # macOS date vs GNU date
        if date -v-7d &>/dev/null 2>&1; then
            WEEK_AGO=$(date -u -v-7d +%Y-%m-%d)
        else
            WEEK_AGO=$(date -u -d '7 days ago' +%Y-%m-%d)
        fi
        DATE_PREFIX=""
        LABEL="Last 7 days (since $WEEK_AGO)"
        ;;
    date)
        DATE_PREFIX="$FILTER_DATE"
        LABEL="Date: $FILTER_DATE"
        ;;
    all)
        DATE_PREFIX=""
        LABEL="All time"
        ;;
esac

# --- Filter log lines ---
if [[ "$RANGE" == "week" ]]; then
    # For week range, filter by comparing dates
    LINES=$(while IFS= read -r line; do
        line_date="${line:0:10}"
        if [[ "$line_date" >= "$WEEK_AGO" ]]; then
            echo "$line"
        fi
    done < "$LOG_FILE")
elif [[ -n "$DATE_PREFIX" ]]; then
    LINES=$(grep "^$DATE_PREFIX" "$LOG_FILE" || true)
else
    LINES=$(cat "$LOG_FILE")
fi

if [[ -z "$LINES" ]]; then
    echo "No log entries for: $LABEL"
    exit 0
fi

# --- Count calls per provider ---
CODEX_CALLS=$(echo "$LINES" | grep -c '\[codex\].*prompt_len' || true)
GEMINI_CALLS=$(echo "$LINES" | grep -c '\[gemini\].*prompt_len' || true)
CODEX_SUCCESS=$(echo "$LINES" | grep -c '\[codex\].*success' || true)
GEMINI_SUCCESS=$(echo "$LINES" | grep -c '\[gemini\].*success' || true)
CODEX_ERRORS=$(echo "$LINES" | grep -c '\[codex\].*\[ERROR\]' || true)
GEMINI_ERRORS=$(echo "$LINES" | grep -c '\[gemini\].*\[ERROR\]' || true)
CODEX_DRYRUN=$(echo "$LINES" | grep -c '\[codex\].*dry run complete' || true)
GEMINI_DRYRUN=$(echo "$LINES" | grep -c '\[gemini\].*dry run complete' || true)

# --- Sum prompt and response lengths ---
CODEX_PROMPT_CHARS=$(echo "$LINES" | grep '\[codex\]' | grep -oE 'prompt_len=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
CODEX_RESP_CHARS=$(echo "$LINES" | grep '\[codex\]' | grep -oE 'response_len=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
GEMINI_PROMPT_CHARS=$(echo "$LINES" | grep '\[gemini\]' | grep -oE 'prompt_len=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
GEMINI_RESP_CHARS=$(echo "$LINES" | grep '\[gemini\]' | grep -oE 'response_len=[0-9]+' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')

TOTAL_PROMPT=$((CODEX_PROMPT_CHARS + GEMINI_PROMPT_CHARS))
TOTAL_RESP=$((CODEX_RESP_CHARS + GEMINI_RESP_CHARS))

# --- Estimate tokens (rough: 1 token ~ 4 chars for English) ---
est_tokens() { echo $(( $1 / 4 )); }

# --- Format numbers with K suffix ---
fmt() {
    local n=$1
    if [[ $n -ge 1000000 ]]; then
        printf "%.1fM" "$(echo "scale=1; $n/1000000" | bc)"
    elif [[ $n -ge 1000 ]]; then
        printf "%.1fK" "$(echo "scale=1; $n/1000" | bc)"
    else
        echo "$n"
    fi
}

# --- Output ---
echo ""
echo -e "${CYAN}Multi-AI Usage Summary${NC}"
echo -e "${DIM}$LABEL${NC}"
echo ""
echo "Provider    Calls  Success  Errors  Dry-run"
echo "─────────── ────── ──────── ─────── ───────"
printf "%-11s %-6s %-8s %-7s %s\n" "Codex" "$CODEX_CALLS" "$CODEX_SUCCESS" "$CODEX_ERRORS" "$CODEX_DRYRUN"
printf "%-11s %-6s %-8s %-7s %s\n" "Gemini" "$GEMINI_CALLS" "$GEMINI_SUCCESS" "$GEMINI_ERRORS" "$GEMINI_DRYRUN"
echo ""
echo "Characters (prompt / response):"
echo "  Codex:  $(fmt $CODEX_PROMPT_CHARS) sent / $(fmt $CODEX_RESP_CHARS) received"
echo "  Gemini: $(fmt $GEMINI_PROMPT_CHARS) sent / $(fmt $GEMINI_RESP_CHARS) received"
echo -e "  ${DIM}Total:  $(fmt $TOTAL_PROMPT) sent / $(fmt $TOTAL_RESP) received${NC}"
echo ""
echo -e "Estimated tokens ${DIM}(~4 chars/token, rough)${NC}:"
echo "  ~$(fmt $(est_tokens $TOTAL_PROMPT)) input + ~$(fmt $(est_tokens $TOTAL_RESP)) output = ~$(fmt $(est_tokens $((TOTAL_PROMPT + TOTAL_RESP)))) total"
echo ""
echo -e "${DIM}Log: $LOG_FILE${NC}"
