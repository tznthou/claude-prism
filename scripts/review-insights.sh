#!/usr/bin/env bash
# review-insights.sh — Analyze review history for recurring patterns
# Usage:
#   review-insights.sh              # full analysis
#   review-insights.sh --recent 10  # last N reviews only
#   review-insights.sh --project X  # filter by project name

set -euo pipefail

LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
INSIGHTS_FILE="$LOG_DIR/review-insights.jsonl"

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Parse args ---
RECENT=0
PROJECT_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --recent)
            [[ $# -ge 2 ]] || { echo "Error: --recent requires a number" >&2; exit 1; }
            RECENT="$2"; shift 2 ;;
        --project)
            [[ $# -ge 2 ]] || { echo "Error: --project requires a name" >&2; exit 1; }
            PROJECT_FILTER="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: review-insights.sh [--recent N] [--project NAME]"
            echo ""
            echo "Options:"
            echo "  --recent N      Analyze only the last N reviews"
            echo "  --project NAME  Filter by project name"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -f "$INSIGHTS_FILE" ]]; then
    echo -e "${YELLOW}No review insights found.${NC}"
    echo ""
    echo "Run /multi-review or /code-review first — insights are recorded automatically."
    echo "Expected file: $INSIGHTS_FILE"
    exit 0
fi

LINE_COUNT=$(wc -l < "$INSIGHTS_FILE" | tr -d ' ')
if [[ "$LINE_COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}Review insights file is empty.${NC}"
    echo "Run /multi-review or /code-review to start recording insights."
    exit 0
fi

# --- Filter lines ---
LINES=$(cat "$INSIGHTS_FILE")

if [[ -n "$PROJECT_FILTER" ]]; then
    LINES=$(echo "$LINES" | grep "\"project\":\"$PROJECT_FILTER\"" || true)
    if [[ -z "$LINES" ]]; then
        echo -e "${YELLOW}No reviews found for project: $PROJECT_FILTER${NC}"
        exit 0
    fi
fi

if [[ "$RECENT" -gt 0 ]]; then
    LINES=$(echo "$LINES" | tail -n "$RECENT")
fi

REVIEW_COUNT=$(echo "$LINES" | wc -l | tr -d ' ')

# --- Extract all issues as flat lines: category|severity|title|source ---
# Using lightweight jq-free parsing with grep/sed
# Each JSONL line has an "issues" array — extract individual issue fields

ISSUES_TMP=$(mktemp "${TMPDIR:-/tmp}/review-insights-XXXXXX.tmp")
trap 'rm -f "$ISSUES_TMP"' EXIT

while IFS= read -r line; do
    # Extract issues array content (between "issues":[ and ])
    issues_raw=$(echo "$line" | sed -n 's/.*"issues":\[\(.*\)\]}.*/\1/p')
    [[ -z "$issues_raw" ]] && continue

    # Split into individual issue objects and extract fields
    # This is a simple parser for well-formed JSON from our own schema
    echo "$issues_raw" | grep -oE '\{[^}]+\}' | while IFS= read -r issue; do
        cat=$(echo "$issue" | grep -oE '"category":"[^"]*"' | head -1 | cut -d'"' -f4)
        sev=$(echo "$issue" | grep -oE '"severity":"[^"]*"' | head -1 | cut -d'"' -f4)
        title=$(echo "$issue" | grep -oE '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
        src=$(echo "$issue" | grep -oE '"source":"[^"]*"' | head -1 | cut -d'"' -f4)
        [[ -n "$cat" ]] && echo "${cat}|${sev}|${title}|${src}"
    done
done <<< "$LINES" > "$ISSUES_TMP" 2>/dev/null

ISSUE_COUNT=0
if [[ -f "$ISSUES_TMP" ]]; then
    ISSUE_COUNT=$(wc -l < "$ISSUES_TMP" | tr -d ' ')
fi

# --- Output header ---
echo ""
echo -e "${CYAN}${BOLD}Review Insights${NC}"
echo -e "${DIM}$REVIEW_COUNT reviews analyzed | $ISSUE_COUNT total issues${NC}"
echo ""

if [[ "$ISSUE_COUNT" -eq 0 ]]; then
    echo "No issues recorded yet."
    rm -f $ISSUES_TMP
    exit 0
fi

# --- Category breakdown ---
echo -e "${BOLD}Issues by Category${NC}"
echo "─────────────────────────────────"
cut -d'|' -f1 $ISSUES_TMP | sort | uniq -c | sort -rn | while read -r count cat; do
    # Color by category
    case "$cat" in
        security)        color="$RED" ;;
        performance)     color="$YELLOW" ;;
        logic)           color="$RED" ;;
        design)          color="$CYAN" ;;
        maintainability) color="$GREEN" ;;
        accessibility)   color="$YELLOW" ;;
        *)               color="$NC" ;;
    esac
    pct=$((count * 100 / ISSUE_COUNT))
    # Simple bar chart
    bar_len=$((pct / 3))
    bar=$(printf '%0.s█' $(seq 1 $((bar_len > 0 ? bar_len : 1))))
    printf "  ${color}%-16s${NC} %3d (%2d%%) %s\n" "$cat" "$count" "$pct" "$bar"
done

# --- Severity breakdown ---
echo ""
echo -e "${BOLD}Issues by Severity${NC}"
echo "─────────────────────────────────"
cut -d'|' -f2 $ISSUES_TMP | sort | uniq -c | sort -rn | while read -r count sev; do
    case "$sev" in
        critical)   color="$RED";    icon="●" ;;
        medium)     color="$YELLOW"; icon="●" ;;
        suggestion) color="$GREEN";  icon="●" ;;
        *)          color="$NC";     icon="○" ;;
    esac
    printf "  ${color}%s %-12s${NC} %3d\n" "$icon" "$sev" "$count"
done

# --- Source breakdown (consensus vs single-provider) ---
echo ""
echo -e "${BOLD}Issue Discovery Source${NC}"
echo "─────────────────────────────────"
cut -d'|' -f4 $ISSUES_TMP | sort | uniq -c | sort -rn | while read -r count src; do
    printf "  %-16s %3d\n" "$src" "$count"
done

# --- Top recurring issues (by title similarity — exact match for now) ---
echo ""
echo -e "${BOLD}Most Frequent Issues${NC}"
echo "─────────────────────────────────"
cut -d'|' -f3 $ISSUES_TMP | sort | uniq -c | sort -rn | head -10 | while read -r count title; do
    if [[ "$count" -gt 1 ]]; then
        printf "  ${YELLOW}%2dx${NC} %s\n" "$count" "$title"
    else
        printf "  %2dx %s\n" "$count" "$title"
    fi
done

# --- Recent review timeline ---
echo ""
echo -e "${BOLD}Recent Reviews${NC}"
echo "─────────────────────────────────"
echo "$LINES" | tail -5 | while IFS= read -r line; do
    date=$(echo "$line" | grep -oE '"date":"[^"]*"' | head -1 | cut -d'"' -f4)
    project=$(echo "$line" | grep -oE '"project":"[^"]*"' | head -1 | cut -d'"' -f4)
    scope=$(echo "$line" | grep -oE '"scope":"[^"]*"' | head -1 | cut -d'"' -f4)
    n_issues=$(echo "$line" | grep -oE '\{[^}]*"category"' | wc -l | tr -d ' ')
    # Truncate date to just date+time
    short_date="${date:0:16}"
    printf "  ${DIM}%s${NC}  %-20s %-12s %d issues\n" "$short_date" "$project" "$scope" "$n_issues"
done

echo ""
echo -e "${DIM}Data: $INSIGHTS_FILE${NC}"
