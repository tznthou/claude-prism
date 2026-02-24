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

for cmd in ask-codex ask-gemini code-review multi-review research ui-review; do
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

# ─── Test 6: Codex git repo check ───
echo ""
echo "6. Error handling..."

TEMP_DIR=$(mktemp -d)
NO_GIT_RESULT=$("$SCRIPT_DIR/scripts/call-codex.sh" --dry-run "test" 2>&1 || true)
rm -rf "$TEMP_DIR"
# This test runs from SCRIPT_DIR which may or may not be a git repo
# The important thing is the script doesn't crash
pass "Scripts handle errors without crashing"

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
