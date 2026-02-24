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

for cmd in ask-codex ask-gemini code-review multi-review research ui-design ui-review; do
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
echo '{"date":"2026-01-01T00:00:00Z","project":"test","scope":"staged","providers":["claude"],"issues":[{"category":"security","severity":"critical","title":"Test issue","source":"claude-only"}]}' > "$TEMP_LOG/review-insights.jsonl"
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

# Dry run (no API keys needed)
DRY_CI=$(echo "fake diff" | "$SCRIPT_DIR/scripts/ci-review.sh" --dry-run 2>&1) || true
if echo "$DRY_CI" | grep -q "\[DRY RUN\]"; then
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

# ─── Test 10: Codex git repo check ───
echo ""
echo "10. Error handling..."

if command -v codex &>/dev/null || [[ -x "$HOME/.npm-global/bin/codex" ]]; then
    TEMP_DIR=$(mktemp -d)
    NO_GIT_RESULT=$(cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/call-codex.sh" "test" 2>&1 || true)
    rm -rf "$TEMP_DIR"
    if echo "$NO_GIT_RESULT" | grep -q "requires a git repo"; then
        pass "call-codex.sh reports clear error outside git repo"
    else
        fail "call-codex.sh no-git error message unexpected: $NO_GIT_RESULT"
    fi
else
    skip "Codex no-git error test skipped (Codex CLI not installed)"
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
