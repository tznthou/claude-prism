#!/usr/bin/env bash
# analyze-log.sh — inspect call-codex.sh / call-gemini.sh lifecycle from multi-ai.log
#
# Diagnoses the Claude Code 2026-04+ auto-background regression by reading
# pid-tagged lifecycle events added in v0.12.3. Groups log entries by pid,
# classifies each invocation:
#   ✅ SUCCESS      — completed normally
#   ❌ ERROR        — CLI returned non-zero, classified by call-*.sh
#   ⚠️  SIGNAL       — caught HUP/INT/TERM (has recorded death stage)
#   ⏱  SOFT_TIMEOUT — v0.14.0+ wall-clock guard fired (CLAUDE_PRISM_TIMEOUT)
#   💀 SILENT       — INVOKE but no outcome — likely SIGKILL from Claude Code
#
# Usage: analyze-log.sh [LOG_FILE]
#        Default: ~/.claude/logs/multi-ai.log
#
# Pre-v0.12.3 log entries have no [pid=N] prefix and are skipped.

set -euo pipefail

LOG_FILE="${1:-$HOME/.claude/logs/multi-ai.log}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: log file not found: $LOG_FILE" >&2
    echo "Usage: $0 [LOG_FILE]" >&2
    exit 1
fi

echo "=== Multi-AI Invocation Analysis ==="
echo "Log: $LOG_FILE"
echo ""

awk '
function to_epoch(ts,   cmd, result) {
    # Reject anything not matching strict ISO-8601 before shell-interpolating.
    # Prevents command injection if the log file is externally tampered — the
    # normal _log write path always produces this format, so zero false negatives
    # for legitimate entries (OWASP A03).
    if (ts !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/) return 0
    # BSD date (macOS) first, GNU date fallback. Silent failure → 0.
    cmd = "date -u -j -f \"%Y-%m-%dT%H:%M:%SZ\" \"" ts "\" +%s 2>/dev/null || date -u -d \"" ts "\" +%s 2>/dev/null || echo 0"
    cmd | getline result
    close(cmd)
    return result + 0
}

function fmt_dur(s) {
    if (s <= 0) return "?"
    if (s < 60)   return s "s"
    if (s < 3600) { m = int(s / 60); r = s % 60; return m "m" (r < 10 ? "0" : "") r "s" }
    h = int(s / 3600); m = int((s % 3600) / 60); return h "h" (m < 10 ? "0" : "") m "m"
}

# v0.12.3+ lifecycle lines have [pid=N] prefix
/\[pid=[0-9]+\]/ {
    ts = $1
    provider = $2; gsub(/[\[\]]/, "", provider)
    level = $3; gsub(/[\[\]]/, "", level)

    match($0, /\[pid=[0-9]+\]/)
    pid = substr($0, RSTART+5, RLENGTH-6)

    msg = substr($0, RSTART + RLENGTH + 1)

    if (msg ~ /^invoke /) {
        invoke_ts[pid] = ts
        invoke_epoch[pid] = to_epoch(ts)
        invoke_provider[pid] = provider
        outcome[pid] = "SILENT"
        last_stage[pid] = "entry"
        if (!(pid in seen)) {
            seen[pid] = 1
            order[++count] = pid
        }
    } else if (msg ~ /^success /) {
        outcome[pid] = "SUCCESS"
        end_epoch[pid] = to_epoch(ts)
        if (match(msg, /response_len=[0-9]+/)) {
            details[pid] = substr(msg, RSTART, RLENGTH)
        }
    } else if (msg ~ /^dry run complete/) {
        outcome[pid] = "SUCCESS"
        end_epoch[pid] = to_epoch(ts)
        details[pid] = "dry-run"
    } else if (msg ~ /^soft_timeout /) {
        # v0.14.0+ wall-clock guard — takes priority over subsequent ERROR/SIGNAL events
        # because call-*.sh logs both after timeout fires (WARN then ERROR), and analyzer
        # would otherwise see the last event win.
        outcome[pid] = "SOFT_TIMEOUT"
        end_epoch[pid] = to_epoch(ts)
        if (match(msg, /elapsed_s=[0-9]+/)) {
            details[pid] = substr(msg, RSTART, RLENGTH)
        } else {
            details[pid] = "soft timeout fired"
        }
    } else if (level == "ERROR") {
        if (outcome[pid] != "SOFT_TIMEOUT") {
            outcome[pid] = "ERROR"
            end_epoch[pid] = to_epoch(ts)
            details[pid] = substr(msg, 1, 80)
        }
    } else if (msg ~ /^signal /) {
        if (outcome[pid] != "SOFT_TIMEOUT") {
            outcome[pid] = "SIGNAL"
            end_epoch[pid] = to_epoch(ts)
            details[pid] = msg
        }
    }

    # Track last observed stage for silent-death forensics
    if (match(msg, /stage=[a-z_]+/) > 0) {
        last_stage[pid] = substr(msg, RSTART+6, RLENGTH-6)
    }
}

END {
    if (count == 0) {
        print "No pid-tagged log entries found."
        print "(Pre-v0.12.3 entries are skipped — they lack the [pid=N] prefix.)"
        exit 0
    }

    n_success = 0; n_error = 0; n_signal = 0; n_soft_timeout = 0; n_silent = 0

    printf "%-7s | %-7s | %-22s | %-8s | %-11s | %s\n", \
        "PID", "Prov", "Started (UTC)", "Duration", "Outcome", "Details"
    print  "--------+---------+------------------------+----------+-------------+-----------------------------------"

    for (i = 1; i <= count; i++) {
        pid = order[i]
        oc = outcome[pid]
        d = details[pid]

        if (oc == "SUCCESS")             { icon = "OK"; n_success++ }
        else if (oc == "ERROR")          { icon = "ER"; n_error++ }
        else if (oc == "SIGNAL")         { icon = "SG"; n_signal++ }
        else if (oc == "SOFT_TIMEOUT")   { icon = "TO"; n_soft_timeout++ }
        else                             { icon = "!!"; n_silent++
                                           d = "last_stage=" last_stage[pid] " (SIGKILL suspected)" }

        dur = (end_epoch[pid] > 0 && invoke_epoch[pid] > 0) ? end_epoch[pid] - invoke_epoch[pid] : -1

        printf "%-7s | %-7s | %-22s | %-8s | %s %-9s | %s\n", \
            pid, invoke_provider[pid], invoke_ts[pid], fmt_dur(dur), icon, oc, d
    }

    print ""
    print "=== Summary ==="
    printf "  OK  Success:      %d\n", n_success
    printf "  ER  Error:        %d\n", n_error
    printf "  SG  Signal:       %d\n", n_signal
    printf "  TO  Soft-timeout: %d\n", n_soft_timeout
    printf "  !!  Silent death: %d", n_silent
    if (n_silent > 0) print "  <- possible Claude Code auto-background SIGKILLs"
    else              print ""
}
' "$LOG_FILE"
