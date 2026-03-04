#!/usr/bin/env bash
# detect-domain.sh — Detect code domain from file paths
# Usage:
#   git diff --name-only | detect-domain.sh
#   detect-domain.sh file1.tsx file2.go
#   echo "src/App.tsx" | detect-domain.sh
#
# Output: "frontend", "backend", or "fullstack" (to stdout)
# Exit code: always 0 (detection should never break the pipeline)

set -uo pipefail
# Note: intentionally no -e — this script guarantees exit 0

LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/multi-ai.log"

# --- Logging ---
_log() {
    local level="$1"; shift
    mkdir -p "$LOG_DIR"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [domain] [$level] $*" >> "$LOG_FILE"
}

# --- Collect file paths ---
FILES=()

# From arguments
if [[ $# -gt 0 ]]; then
    FILES=("$@")
fi

# From stdin (if not a terminal)
if [[ ! -t 0 ]]; then
    while IFS= read -r line; do
        [[ -n "$line" ]] && FILES+=("$line")
    done
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
    _log INFO "no files provided, defaulting to fullstack"
    echo "fullstack"
    exit 0
fi

# --- Classify each file ---
frontend=0
backend=0

for file in "${FILES[@]}"; do
    # Extract extension (lowercase, portable — macOS ships bash 3.2)
    ext="${file##*.}"
    ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

    # Extract path for directory-based matching (lowercase)
    path="$(printf '%s' "$file" | tr '[:upper:]' '[:lower:]')"

    matched=false

    # Frontend extensions
    case "$ext" in
        css|scss|sass|less|styl|tsx|jsx|vue|svelte|html|svg)
            frontend=$((frontend + 1))
            matched=true
            ;;
    esac

    # Backend extensions
    if [[ "$matched" == false ]]; then
        case "$ext" in
            go|py|rs|java|rb|ex|exs|sql|prisma|proto)
                backend=$((backend + 1))
                matched=true
                ;;
        esac
    fi

    # Path-based detection (only if extension was neutral)
    if [[ "$matched" == false ]]; then
        case "$path" in
            *components/*|*pages/*|*views/*|*layouts/*|*styles/*|*ui/*|*public/*|*assets/*)
                frontend=$((frontend + 1))
                ;;
            *api/*|*routes/*|*controllers/*|*models/*|*services/*|*middleware/*|*migrations/*|*db/*|*handlers/*|*cmd/*|*internal/*|*pkg/*)
                backend=$((backend + 1))
                ;;
        esac
    fi
done

# --- Determine domain ---
total=$((frontend + backend))

if [[ $total -eq 0 ]]; then
    domain="fullstack"
elif [[ $((frontend * 10 / total)) -ge 7 ]]; then
    domain="frontend"
elif [[ $((backend * 10 / total)) -ge 7 ]]; then
    domain="backend"
else
    domain="fullstack"
fi

_log INFO "files=${#FILES[@]} frontend=$frontend backend=$backend domain=$domain"
echo "$domain"
