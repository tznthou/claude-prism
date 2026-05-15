#!/usr/bin/env bash
# scripts/calibrate-timeout.sh (v03) — per-skill timeout calibrator
#
# Reads dated wrapper logs (multi-ai-YYYY-MM.log), computes per-skill
# p99/median/suggested timeout with class-aware clamping.
#
# Class mapping (frozen v0.14.4 + commit 71f997d):
#   heavy (5): pi-askall/fact-check/plan/multi-review/code-review → floor 480 / ceiling 540
#   small (5): pi-ask-codex/ask-gemini/research/ui-design/ui-review → floor 240 / ceiling 300
#
# Formula: suggested = clamp(class_floor, class_ceiling, ceil(p99 * 1.15 / 10) * 10)
# N<5: stick with current (low confidence)
# Non-pi caller: no suggestion (informational only)

set -uo pipefail

LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
LOG_GLOB="$LOG_DIR/multi-ai-[0-9][0-9][0-9][0-9]-[0-9][0-9].log"
APPLY=false
BUFFER_PCT=15
MIN_N=5

for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=true ;;
        --buffer=*) BUFFER_PCT="${arg#--buffer=}" ;;
        --min-n=*) MIN_N="${arg#--min-n=}" ;;
        --help|-h)
            cat <<HELP
calibrate-timeout.sh — per-skill timeout from wrapper log

Usage:
  calibrate-timeout.sh                  report only (default)
  calibrate-timeout.sh --apply          update commands/pi-*.md TIMEOUT
  calibrate-timeout.sh --buffer=18      buffer % above p99 (default 15)
  calibrate-timeout.sh --min-n=8        minimum N for suggestion (default 5)

Formula: suggested = clamp(class_floor, class_ceiling, ceil(p99 * (1+buffer/100) / 10) * 10)
Class:   heavy [480-540s] / small [240-300s] (frozen v0.14.4 mapping)

Env: MULTI_AI_LOG_DIR overrides log location (default ~/.claude/logs)
HELP
            exit 0 ;;
    esac
done

shopt -s nullglob
# shellcheck disable=SC2206  # intentional glob expansion; nullglob handles no-match case
LOG_FILES=( $LOG_GLOB )
shopt -u nullglob

if [ ${#LOG_FILES[@]} -eq 0 ]; then
    echo "no data: no log files matching $LOG_GLOB" >&2
    exit 0
fi

# Pass 1: extract pid → caller, pid → elapsed (success), error pids
RAW=$(awk '
function extract_pid(line) {
    if (match(line, /\[pid=[0-9]+\]/)) return substr(line, RSTART+5, RLENGTH-6) + 0
    return 0
}
function extract_caller(line) {
    if (match(line, /caller="[^"]+"/)) return substr(line, RSTART+8, RLENGTH-9)
    return ""
}
function extract_elapsed(line) {
    if (match(line, /elapsed_s=[0-9]+/)) return substr(line, RSTART+10, RLENGTH-10) + 0
    return 0
}
/\[INFO\].*invoke ppid.*caller="/ {
    pid = extract_pid($0); caller = extract_caller($0)
    if (pid && caller) callers[pid] = caller
}
/\[INFO\].*success response_len/ {
    pid = extract_pid($0); elapsed = extract_elapsed($0)
    if (pid && (pid in callers) && !(pid in error_pids)) {
        successes[pid] = callers[pid] "|" elapsed
    }
}
/\[ERROR\]/ {
    pid = extract_pid($0)
    if (pid) { error_pids[pid] = 1; delete successes[pid] }
    if (pid in callers) err_count[callers[pid]]++
    else err_count["unknown"]++
}
END {
    for (pid in successes) print "S|" successes[pid]
    for (c in err_count) print "E|" c "|" err_count[c]
    unknown_n = 0
    for (pid in callers) if (callers[pid] == "unknown") unknown_n++
    print "U|" unknown_n
}
' "${LOG_FILES[@]}")

# Pass 2: aggregate + class-aware clamping + suggestion emission
SUGGEST_FILE=$(mktemp "${TMPDIR:-/tmp}/calibrate-suggest-XXXXXX")
trap 'rm -f "$SUGGEST_FILE"' EXIT

echo "$RAW" | \
    BUFFER_PCT="$BUFFER_PCT" \
    MIN_N="$MIN_N" \
    SUGGEST_FILE="$SUGGEST_FILE" \
    awk -F'|' '
BEGIN {
    buffer_pct = ENVIRON["BUFFER_PCT"] + 0
    min_n = ENVIRON["MIN_N"] + 0
    suggest_file = ENVIRON["SUGGEST_FILE"]
    # Heavy class (frozen 5 skills)
    heavy["pi-askall"] = 1; heavy["pi-fact-check"] = 1; heavy["pi-plan"] = 1
    heavy["pi-multi-review"] = 1; heavy["pi-code-review"] = 1
    FLOOR_HEAVY = 480; CEILING_HEAVY = 540
    FLOOR_SMALL = 240; CEILING_SMALL = 300
}
$1 == "S" {
    caller = $2; elapsed = $3 + 0
    elapsed_list[caller] = elapsed_list[caller] ? elapsed_list[caller] " " elapsed : elapsed
    n[caller]++
}
$1 == "E" { err[$2] = $3 + 0 }
$1 == "U" { unknown_total = $2 + 0 }
END {
    printf "\n=== per-skill timeout calibration ===\n"
    printf "%-22s %4s %8s %8s %8s %8s %s\n", "caller", "N", "median", "p99", "max", "raw", "suggested"
    printf "%-22s %4s %8s %8s %8s %8s %s\n", "----------------------", "----", "--------", "--------", "--------", "--------", "------------"
    for (c in elapsed_list) {
        cnt = n[c]
        split(elapsed_list[c], arr, " ")
        for (i=1; i<=cnt; i++) for (j=i+1; j<=cnt; j++) if (arr[i]+0 > arr[j]+0) { t=arr[i]; arr[i]=arr[j]; arr[j]=t }

        is_pi = (substr(c, 1, 3) == "pi-")
        if (c in heavy) { fl = FLOOR_HEAVY; ce = CEILING_HEAVY; cls = "heavy" }
        else if (is_pi) { fl = FLOOR_SMALL; ce = CEILING_SMALL; cls = "small" }
        else { fl = 0; ce = 0; cls = "n/a" }

        if (cnt < 3) {
            printf "%-22s %4d %8s %8s %8d %8s %s\n", c, cnt, "-", "-", arr[cnt], "-", "(N<3 insufficient)"
            continue
        }
        mid = arr[int((cnt+1)/2)]
        p99_idx = int(cnt * 0.99 + 0.5)
        if (p99_idx < 1) p99_idx = 1
        if (p99_idx > cnt) p99_idx = cnt
        p99v = arr[p99_idx]
        raw = int((p99v * (100 + buffer_pct) / 100 + 9) / 10) * 10

        if (fl == 0) {
            # Non-pi caller: informational, no suggestion
            printf "%-22s %4d %8d %8d %8d %8d (no-class)\n", c, cnt, mid, p99v, arr[cnt], raw
            continue
        }

        sug = raw
        clamp_note = ""
        if (sug < fl) { sug = fl; clamp_note = "↑floor" }
        else if (sug > ce) { sug = ce; clamp_note = "↓ceil" }

        if (cnt < min_n) {
            printf "%-22s %4d %8d %8d %8d %8d (N<%d low-conf, keep current)\n", c, cnt, mid, p99v, arr[cnt], raw, min_n
        } else {
            printf "%-22s %4d %8d %8d %8d %8d %d %s (%s)\n", c, cnt, mid, p99v, arr[cnt], raw, sug, clamp_note, cls
            printf "SUGGEST|%s|%d\n", c, sug > suggest_file
        }
    }
    if (length(err) > 0) {
        printf "\n=== errors (excluded from p99) ===\n"
        for (c in err) printf "  %-20s %4d\n", c, err[c]
    }
    if (unknown_total > 0) {
        printf "\n[WARN] %d invocations with caller=\"unknown\" — caller env-var not propagated\n", unknown_total
    }
}'

if ! $APPLY; then
    exit 0
fi

# --apply: update commands/pi-*.md
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_DIR="$SCRIPT_DIR/commands"
if [ ! -d "$CMD_DIR" ]; then
    echo "[ERROR] commands/ not found at $CMD_DIR" >&2
    exit 1
fi

echo ""
echo "=== applying suggestions to commands/pi-*.md ==="
updated=0; skipped=0; noop=0
while IFS='|' read -r tag caller sug; do
    [ "$tag" = "SUGGEST" ] || continue
    f="$CMD_DIR/${caller}.md"
    if [ ! -f "$f" ]; then
        echo "  skip: $caller (no $f)" >&2
        skipped=$((skipped + 1))
        continue
    fi
    current=$(grep -oE 'CLAUDE_PRISM_TIMEOUT=[0-9]+' "$f" | head -1 | awk -F= '{print $2}')
    if [ -z "$current" ]; then
        echo "  skip: $caller (no CLAUDE_PRISM_TIMEOUT line)" >&2
        skipped=$((skipped + 1))
        continue
    fi
    if [ "$current" = "$sug" ]; then
        echo "  noop: $caller (already $sug)"
        noop=$((noop + 1))
        continue
    fi
    sed -i.bak -E "s/CLAUDE_PRISM_TIMEOUT=${current}/CLAUDE_PRISM_TIMEOUT=${sug}/g" "$f"
    rm -f "$f.bak"
    echo "  update: $caller $current → $sug"
    updated=$((updated + 1))
done < "$SUGGEST_FILE"
echo "=== applied: $updated updated, $noop noop, $skipped skipped ==="
