#!/usr/bin/env bash
# smoke-test.sh — Verify that scripts and CLIs are functional
# Usage: ./tests/smoke-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "  ${GREEN}PASS${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $*"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC} $*"; SKIP=$((SKIP + 1)); }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   claude-prism smoke test                ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── Test 1: Scripts exist and are executable ───
echo "1. Script files..."

for script in call-gemini.sh call-codex.sh; do
    if [[ -x "$SCRIPT_DIR/scripts/$script" ]]; then
        pass "$script exists and is executable"
    else
        fail "$script missing or not executable"
    fi
done

# ─── Test 2: Commands exist ───
echo ""
echo "2. Command files..."

for cmd in pi-ask-codex pi-ask-gemini pi-code-review pi-multi-review pi-plan pi-research pi-ui-design pi-ui-review; do
    if [[ -f "$SCRIPT_DIR/commands/$cmd.md" ]]; then
        pass "/$(basename "$cmd") command definition exists"
    else
        fail "/$(basename "$cmd") command definition missing"
    fi
done

# ─── Test 3: CLI availability ───
echo ""
echo "3. External CLI availability..."

# Gemini
if command -v gemini &>/dev/null || [[ -x "$HOME/.npm-global/bin/gemini" ]]; then
    pass "Gemini CLI available"
else
    skip "Gemini CLI not installed (optional)"
fi

# Codex
if command -v codex &>/dev/null || [[ -x "$HOME/.npm-global/bin/codex" ]]; then
    pass "Codex CLI available"
else
    skip "Codex CLI not installed (optional)"
fi

# ─── Test 4: Dry run ───
echo ""
echo "4. Dry run tests..."

# Gemini dry run
DRY_GEMINI=$("$SCRIPT_DIR/scripts/call-gemini.sh" --dry-run "hello" 2>&1) || true
if echo "$DRY_GEMINI" | grep -q "\[DRY RUN\]"; then
    pass "call-gemini.sh --dry-run works"
else
    fail "call-gemini.sh --dry-run unexpected output: $DRY_GEMINI"
fi

# Codex dry run (needs git repo)
TEMP_REPO=$(mktemp -d)
git -C "$TEMP_REPO" init -q
DRY_CODEX=$(cd "$TEMP_REPO" && "$SCRIPT_DIR/scripts/call-codex.sh" --dry-run "hello" 2>&1) || true
rm -rf "$TEMP_REPO"
if echo "$DRY_CODEX" | grep -q "\[DRY RUN\]"; then
    pass "call-codex.sh --dry-run works"
else
    fail "call-codex.sh --dry-run unexpected output: $DRY_CODEX"
fi

# ─── Test 5: Logging ───
echo ""
echo "5. Logging..."

LOG_DIR="${MULTI_AI_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/multi-ai.log"

if [[ -f "$LOG_FILE" ]]; then
    RECENT=$(tail -2 "$LOG_FILE" | grep -c "dry_run=true" || true)
    if [[ "$RECENT" -ge 1 ]]; then
        pass "Dry run calls were logged to $LOG_FILE"
    else
        fail "Log file exists but dry run entries not found"
    fi
else
    fail "Log file not created at $LOG_FILE"
fi

# ─── Test 6: Usage summary script ───
echo ""
echo "6. Usage summary..."

if [[ -x "$SCRIPT_DIR/scripts/usage-summary.sh" ]]; then
    pass "usage-summary.sh exists and is executable"
else
    fail "usage-summary.sh missing or not executable"
fi

# Dry run to generate some log entries, then test summary
SUMMARY_OUT=$("$SCRIPT_DIR/scripts/usage-summary.sh" --all 2>&1) || true
if echo "$SUMMARY_OUT" | grep -q "Provider"; then
    pass "usage-summary.sh --all produces output"
else
    # May have no log entries yet — that's OK
    if echo "$SUMMARY_OUT" | grep -q "No log"; then
        pass "usage-summary.sh --all handles empty logs"
    else
        fail "usage-summary.sh unexpected output: $SUMMARY_OUT"
    fi
fi

# ─── Test 7: Review insights script ───
echo ""
echo "7. Review insights..."

if [[ -x "$SCRIPT_DIR/scripts/review-insights.sh" ]]; then
    pass "review-insights.sh exists and is executable"
else
    fail "review-insights.sh missing or not executable"
fi

# Test with synthetic data
TEMP_LOG=$(mktemp -d)
echo '{"date":"2026-01-01T00:00:00Z","project":"test","scope":"staged","domain":"fullstack","providers":["claude"],"issues":[{"category":"security","severity":"critical","confidence":85,"title":"Test issue","source":"claude-only"}]}' > "$TEMP_LOG/review-insights.jsonl"
INSIGHTS_OUT=$(MULTI_AI_LOG_DIR="$TEMP_LOG" "$SCRIPT_DIR/scripts/review-insights.sh" 2>&1) || true
rm -rf "$TEMP_LOG"
if echo "$INSIGHTS_OUT" | grep -q "Issues by Category"; then
    pass "review-insights.sh parses JSONL and produces report"
else
    fail "review-insights.sh unexpected output"
fi

# Test empty state (no file)
EMPTY_DIR=$(mktemp -d)
EMPTY_OUT=$(MULTI_AI_LOG_DIR="$EMPTY_DIR" "$SCRIPT_DIR/scripts/review-insights.sh" 2>&1) || true
rm -rf "$EMPTY_DIR"
if echo "$EMPTY_OUT" | grep -q "No review insights"; then
    pass "review-insights.sh handles missing file gracefully"
else
    fail "review-insights.sh empty state handling unexpected"
fi

# ─── Test 8: CI review script ───
echo ""
echo "8. CI review script..."

if [[ -x "$SCRIPT_DIR/scripts/ci-review.sh" ]]; then
    pass "ci-review.sh exists and is executable"
else
    fail "ci-review.sh missing or not executable"
fi

# Dry run (no API keys needed, --dry-run exits before reading input)
DRY_CI=$("$SCRIPT_DIR/scripts/ci-review.sh" --dry-run 2>&1) || true
if [[ "$DRY_CI" == *"[DRY RUN]"* ]]; then
    pass "ci-review.sh --dry-run works"
else
    fail "ci-review.sh --dry-run unexpected output: $DRY_CI"
fi

# No input and no API keys → error
NO_INPUT_RESULT=$("$SCRIPT_DIR/scripts/ci-review.sh" 2>&1 || true)
if echo "$NO_INPUT_RESULT" | grep -qi "error"; then
    pass "ci-review.sh reports error when no input provided"
else
    fail "ci-review.sh no-input error handling unexpected: $NO_INPUT_RESULT"
fi

# ─── Test 9: GitHub Actions workflow ───
echo ""
echo "9. GitHub Actions workflow..."

if [[ -f "$SCRIPT_DIR/.github/workflows/ai-review.yml" ]]; then
    pass "ai-review.yml workflow exists"
else
    fail "ai-review.yml workflow missing"
fi

# ─── Test 10: Domain detection ───
echo ""
echo "10. Domain detection..."

if [[ -x "$SCRIPT_DIR/scripts/detect-domain.sh" ]]; then
    pass "detect-domain.sh exists and is executable"
else
    fail "detect-domain.sh missing or not executable"
fi

# Pure frontend
result=$(printf 'src/App.tsx\ncomponents/Header.tsx\nstyles/main.css\n' \
    | "$SCRIPT_DIR/scripts/detect-domain.sh")
if [[ "$result" == "frontend" ]]; then
    pass "detect-domain: pure frontend → frontend"
else
    fail "detect-domain: pure frontend expected 'frontend', got '$result'"
fi

# Pure backend
result=$(printf 'api/handler.go\nmodels/user.go\nmigrations/001.sql\n' \
    | "$SCRIPT_DIR/scripts/detect-domain.sh")
if [[ "$result" == "backend" ]]; then
    pass "detect-domain: pure backend → backend"
else
    fail "detect-domain: pure backend expected 'backend', got '$result'"
fi

# Mixed → fullstack
result=$(printf 'src/App.tsx\napi/handler.go\n' \
    | "$SCRIPT_DIR/scripts/detect-domain.sh")
if [[ "$result" == "fullstack" ]]; then
    pass "detect-domain: mixed → fullstack"
else
    fail "detect-domain: mixed expected 'fullstack', got '$result'"
fi

# Empty input → fullstack
result=$(echo "" | "$SCRIPT_DIR/scripts/detect-domain.sh")
if [[ "$result" == "fullstack" ]]; then
    pass "detect-domain: empty input → fullstack"
else
    fail "detect-domain: empty input expected 'fullstack', got '$result'"
fi

# Neutral extensions → fullstack
result=$(printf 'utils/helper.ts\nconfig.json\nindex.js\n' \
    | "$SCRIPT_DIR/scripts/detect-domain.sh")
if [[ "$result" == "fullstack" ]]; then
    pass "detect-domain: neutral files → fullstack"
else
    fail "detect-domain: neutral expected 'fullstack', got '$result'"
fi

# ─── Test 11: Codex sandbox downgrade outside git repo ───
echo ""
echo "11. Error handling..."

if command -v codex &>/dev/null || [[ -x "$HOME/.npm-global/bin/codex" ]]; then
    TEMP_DIR=$(mktemp -d)
    NO_GIT_RESULT=$(cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/call-codex.sh" --dry-run "test" 2>&1 || true)
    rm -rf "$TEMP_DIR"
    if echo "$NO_GIT_RESULT" | grep -q "sandbox downgraded to 'none'"; then
        pass "call-codex.sh downgrades sandbox outside git repo"
    else
        fail "call-codex.sh no-git sandbox downgrade message unexpected: $NO_GIT_RESULT"
    fi
else
    skip "Codex no-git sandbox test skipped (Codex CLI not installed)"
fi

# ─── Test 12: Stdin regression scenarios ───
# Guards against the v0.12.3→v0.12.5 bug shapes: silent drop on file redirect,
# deadlock on non-EOF stdin. Any edit to the stdin block in call-{codex,gemini}.sh
# must keep these six cases green. Assertions check exact prompt_len so that a
# silent truncation (appending only separators or fragments of stdin) still fails.
#
# Intentionally excluded: inherited non-EOF fd (anonymous pipe via /dev/fd). FIFO
# is not a valid proxy (guard's -p predicate returns true for named pipes, so it
# blocks on cat instead of skipping), and macOS lacks `timeout`. See
# .claude/pi-plans/stdin-duplication-evaluation.md Simplify Review for details.
echo ""
echo "12. Stdin regression..."

STDIN_FIXTURE_DIR=$(mktemp -d)
STDIN_CODEX_REPO=$(mktemp -d)
T13_DIR=""
T13_LOGDIRS=()
# shellcheck disable=SC2329  # invoked via trap
_t12_t13_cleanup() {
    rm -rf "$STDIN_FIXTURE_DIR" "$STDIN_CODEX_REPO" ${T13_DIR:+"$T13_DIR"} "${T13_LOGDIRS[@]}"
}
trap _t12_t13_cleanup EXIT

STDIN_FIXTURE="$STDIN_FIXTURE_DIR/fixture.txt"
STDIN_PAYLOAD="hi from stdin"
printf '%s\n' "$STDIN_PAYLOAD" > "$STDIN_FIXTURE"

# Prompt length accounting when guard consumes stdin:
#   PROMPT = "q" + "\n\n" + STDIN_DATA
# STDIN_DATA is $(cat), which strips the trailing newline echo/printf adds, so
# it equals STDIN_PAYLOAD byte-for-byte. Expected = 1 + 2 + len(payload).
STDIN_EXPECT_CONSUMED=$(( 1 + 2 + ${#STDIN_PAYLOAD} ))
STDIN_EXPECT_SKIPPED=1

git -C "$STDIN_CODEX_REPO" init -q

_check_prompt_len() {
    local label="$1" output="$2" expected="$3" len
    len=$(grep -oE 'Prompt length: [0-9]+' <<< "$output" | grep -oE '[0-9]+' | head -1 || true)
    if [[ "$len" == "$expected" ]]; then
        pass "$label (prompt_len=$len)"
    else
        fail "$label: expected len=$expected, got '$len'"
    fi
}

STDIN_OUT=$(printf '%s\n' "$STDIN_PAYLOAD" | "$SCRIPT_DIR/scripts/call-gemini.sh" --dry-run "q" 2>&1 || true)
_check_prompt_len "call-gemini.sh stdin via pipe" "$STDIN_OUT" "$STDIN_EXPECT_CONSUMED"

STDIN_OUT=$("$SCRIPT_DIR/scripts/call-gemini.sh" --dry-run "q" < "$STDIN_FIXTURE" 2>&1 || true)
_check_prompt_len "call-gemini.sh stdin via file redirect" "$STDIN_OUT" "$STDIN_EXPECT_CONSUMED"

STDIN_OUT=$("$SCRIPT_DIR/scripts/call-gemini.sh" --dry-run "q" < /dev/null 2>&1 || true)
_check_prompt_len "call-gemini.sh stdin from /dev/null skipped" "$STDIN_OUT" "$STDIN_EXPECT_SKIPPED"

STDIN_OUT=$(cd "$STDIN_CODEX_REPO" && printf '%s\n' "$STDIN_PAYLOAD" | "$SCRIPT_DIR/scripts/call-codex.sh" --dry-run "q" 2>&1 || true)
_check_prompt_len "call-codex.sh stdin via pipe" "$STDIN_OUT" "$STDIN_EXPECT_CONSUMED"

STDIN_OUT=$(cd "$STDIN_CODEX_REPO" && "$SCRIPT_DIR/scripts/call-codex.sh" --dry-run "q" < "$STDIN_FIXTURE" 2>&1 || true)
_check_prompt_len "call-codex.sh stdin via file redirect" "$STDIN_OUT" "$STDIN_EXPECT_CONSUMED"

STDIN_OUT=$(cd "$STDIN_CODEX_REPO" && "$SCRIPT_DIR/scripts/call-codex.sh" --dry-run "q" < /dev/null 2>&1 || true)
_check_prompt_len "call-codex.sh stdin from /dev/null skipped" "$STDIN_OUT" "$STDIN_EXPECT_SKIPPED"

# Cleanup handled by EXIT trap set above.

# ─── Test 13: Soft-timeout regression scenarios (v0.14.0+) ───
# Guards against regressions in the CLAUDE_PRISM_TIMEOUT wall-clock guard block
# in call-{codex,gemini}.sh. Uses fake CLI binaries (shell scripts) injected via
# CODEX_BIN / GEMINI_BIN env vars so no real API calls are made.
# 5 assertions: normal path (rc=0), timeout fires (rc=124 + sentinel + log event),
# custom TIMEOUT=5 honoured, no orphan processes, gemini mirror fires identically.
echo ""
echo "13. Soft-timeout regression..."

T13_DIR=$(mktemp -d)
T13_FAKE_SLOW="$T13_DIR/fake-slow-cli"
T13_FAKE_FAST="$T13_DIR/fake-fast-cli"

cat > "$T13_FAKE_SLOW" <<'FAKESLOW'
#!/bin/bash
# Consume stdin first (avoids SIGPIPE on printf upstream), then hang.
cat > /dev/null 2>&1 || true
sleep 30
echo "slow-done"
FAKESLOW
chmod +x "$T13_FAKE_SLOW"

cat > "$T13_FAKE_FAST" <<'FAKEFAST'
#!/bin/bash
cat > /dev/null 2>&1 || true
echo "fake-done"
FAKEFAST
chmod +x "$T13_FAKE_FAST"

# T13.1 Normal completion under timeout (codex, fast CLI, TIMEOUT=10)
T13_LD1=$(mktemp -d); T13_LOGDIRS+=("$T13_LD1")
set +e
MULTI_AI_LOG_DIR="$T13_LD1" CODEX_BIN="$T13_FAKE_FAST" CLAUDE_PRISM_TIMEOUT=10 \
    "$SCRIPT_DIR/scripts/call-codex.sh" "q" > "$T13_LD1/out" 2> "$T13_LD1/err"
T13_RC1=$?
set -e
if [[ $T13_RC1 -eq 0 ]] && \
   ! grep -q "CLAUDE-PRISM: soft-timeout" "$T13_LD1/err" && \
   ! grep -q "soft_timeout" "$T13_LD1/multi-ai.log" && \
   grep -q "success response_len" "$T13_LD1/multi-ai.log"; then
    pass "T13.1 codex normal completion under timeout (rc=0, no sentinel, no soft_timeout log event)"
else
    fail "T13.1 codex normal: expected rc=0 + no sentinel + no soft_timeout log + success log, got rc=$T13_RC1; err=$(cat "$T13_LD1/err")"
fi

# T13.2 Timeout fires (codex, slow CLI, TIMEOUT=2)
T13_LD2=$(mktemp -d); T13_LOGDIRS+=("$T13_LD2")
set +e
MULTI_AI_LOG_DIR="$T13_LD2" CODEX_BIN="$T13_FAKE_SLOW" CLAUDE_PRISM_TIMEOUT=2 \
    "$SCRIPT_DIR/scripts/call-codex.sh" "q" > "$T13_LD2/out" 2> "$T13_LD2/err"
T13_RC2=$?
set -e
if [[ $T13_RC2 -eq 124 ]] && \
   grep -q "CLAUDE-PRISM: soft-timeout at STAGE=exec after 2s" "$T13_LD2/err" && \
   grep -q "soft_timeout stage=exec elapsed_s=2" "$T13_LD2/multi-ai.log"; then
    pass "T13.2 codex timeout fires (rc=124 + sentinel + log event)"
else
    fail "T13.2 codex timeout: expected rc=124 + sentinel + log, got rc=$T13_RC2; err=$(cat "$T13_LD2/err")"
fi

# T13.3 Custom CLAUDE_PRISM_TIMEOUT=5 honoured (~5s, tolerance ±2s)
T13_LD3=$(mktemp -d); T13_LOGDIRS+=("$T13_LD3")
T13_START=$(date +%s)
set +e
MULTI_AI_LOG_DIR="$T13_LD3" CODEX_BIN="$T13_FAKE_SLOW" CLAUDE_PRISM_TIMEOUT=5 \
    "$SCRIPT_DIR/scripts/call-codex.sh" "q" > /dev/null 2>&1
set -e
T13_ELAPSED=$(( $(date +%s) - T13_START ))
if (( T13_ELAPSED >= 3 && T13_ELAPSED <= 8 )); then
    pass "T13.3 codex custom TIMEOUT=5 honoured (elapsed=${T13_ELAPSED}s)"
else
    fail "T13.3 codex custom TIMEOUT=5: expected elapsed~5s, got ${T13_ELAPSED}s"
fi

# T13.4 No orphan processes after timeout fires
# Brief settle delay to let OS reap zombies.
sleep 1
T13_ORPHAN=$(pgrep -f "fake-slow-cli" 2>/dev/null | head -3 || true)
if [[ -z "$T13_ORPHAN" ]]; then
    pass "T13.4 no orphan fake-slow-cli processes after timeout fires"
else
    fail "T13.4 orphan pids found: $T13_ORPHAN"
fi

# T13.6 Invalid TIMEOUT value (Codex review Finding 1 regression guard):
# Large values like 9999999999 are rejected by macOS BSD sleep, which would
# silently disable the timeout guard entirely if the validation only checked
# integer format. Upper bound 3600 forces these into the fallback path.
T13_LD6=$(mktemp -d); T13_LOGDIRS+=("$T13_LD6")
set +e
MULTI_AI_LOG_DIR="$T13_LD6" CODEX_BIN="$T13_FAKE_FAST" CLAUDE_PRISM_TIMEOUT=9999999999 \
    "$SCRIPT_DIR/scripts/call-codex.sh" "q" > "$T13_LD6/out" 2> "$T13_LD6/err"
T13_RC6=$?
set -e
if [[ $T13_RC6 -eq 0 ]] && \
   grep -q "invalid CLAUDE_PRISM_TIMEOUT=9999999999" "$T13_LD6/multi-ai.log" && \
   grep -q "success response_len" "$T13_LD6/multi-ai.log"; then
    pass "T13.6 overflow TIMEOUT falls back to 110 with WARN log (Finding 1 regression guard)"
else
    fail "T13.6 overflow TIMEOUT: expected rc=0 + WARN fallback log, got rc=$T13_RC6"
fi

# T13.5 Gemini mirror fires identically (sanity check on byte-sync)
T13_LD5=$(mktemp -d); T13_LOGDIRS+=("$T13_LD5")
set +e
MULTI_AI_LOG_DIR="$T13_LD5" GEMINI_BIN="$T13_FAKE_SLOW" CLAUDE_PRISM_TIMEOUT=2 \
    "$SCRIPT_DIR/scripts/call-gemini.sh" "q" > "$T13_LD5/out" 2> "$T13_LD5/err"
T13_RC5=$?
set -e
if [[ $T13_RC5 -eq 124 ]] && \
   grep -q "CLAUDE-PRISM: soft-timeout at STAGE=exec after 2s" "$T13_LD5/err" && \
   grep -q "\[gemini\].*soft_timeout stage=exec elapsed_s=2" "$T13_LD5/multi-ai.log"; then
    pass "T13.5 gemini timeout mirrors codex (rc=124 + sentinel + [gemini] log event)"
else
    fail "T13.5 gemini timeout: expected rc=124 + sentinel + [gemini] log, got rc=$T13_RC5"
fi

# ─── Summary ───
echo ""
echo "─────────────────────────────────────────"
TOTAL=$((PASS + FAIL + SKIP))
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC} (total: $TOTAL)"

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
