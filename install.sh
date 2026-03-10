#!/usr/bin/env bash
# install.sh — Install claude-prism commands and scripts
# Usage: ./install.sh [--check-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CHECK_ONLY=false

if [[ "${1:-}" == "--check-only" ]]; then
    CHECK_ONLY=true
fi

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
info() { echo -e "  ${CYAN}→${NC} $*"; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   claude-prism installer                 ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── Check prerequisites ───
echo "Checking prerequisites..."

PREREQ_OK=true

# Claude Code
if command -v claude &>/dev/null; then
    ok "Claude Code CLI found"
else
    warn "Claude Code CLI not found (not strictly required, but this toolkit is built for it)"
fi

# Gemini CLI
if command -v gemini &>/dev/null; then
    GEMINI_VER=$(gemini --version 2>/dev/null || echo "unknown")
    ok "Gemini CLI found (v$GEMINI_VER)"
else
    # Check npm global
    if [[ -x "$HOME/.npm-global/bin/gemini" ]]; then
        ok "Gemini CLI found at ~/.npm-global/bin/gemini"
    else
        warn "Gemini CLI not found — /pi-ask-gemini, /pi-ui-design, /pi-ui-review, /pi-research will not work"
        info "Install: npm install -g @google/gemini-cli"
        PREREQ_OK=false
    fi
fi

# Codex CLI
if command -v codex &>/dev/null; then
    ok "Codex CLI found"
else
    if [[ -x "$HOME/.npm-global/bin/codex" ]]; then
        ok "Codex CLI found at ~/.npm-global/bin/codex"
    else
        warn "Codex CLI not found — /pi-ask-codex, /pi-code-review will not work"
        info "Install: npm install -g @openai/codex"
        PREREQ_OK=false
    fi
fi

echo ""

if [[ "$CHECK_ONLY" == true ]]; then
    if [[ "$PREREQ_OK" == true ]]; then
        ok "All prerequisites met!"
    else
        warn "Some prerequisites missing (see above). Commands that depend on missing CLIs will not work."
    fi
    exit 0
fi

# ─── Backup existing files (single pass: detect + copy) ───
BACKUP_DIR="$CLAUDE_DIR/.multi-ai-backup-$(date +%Y%m%d%H%M%S)"
BACKED_UP=false

for cmd in "$SCRIPT_DIR"/commands/*.md; do
    target="$CLAUDE_DIR/commands/$(basename "$cmd")"
    if [[ -f "$target" ]]; then
        [[ "$BACKED_UP" == false ]] && mkdir -p "$BACKUP_DIR/commands" "$BACKUP_DIR/scripts"
        cp "$target" "$BACKUP_DIR/commands/"
        BACKED_UP=true
    fi
done

for script in "$SCRIPT_DIR"/scripts/*.sh; do
    target="$CLAUDE_DIR/scripts/$(basename "$script")"
    if [[ -f "$target" ]]; then
        [[ "$BACKED_UP" == false ]] && mkdir -p "$BACKUP_DIR/commands" "$BACKUP_DIR/scripts"
        cp "$target" "$BACKUP_DIR/scripts/"
        BACKED_UP=true
    fi
done

[[ "$BACKED_UP" == true ]] && info "Existing files backed up to $BACKUP_DIR"

# ─── Verify integrity (if checksums available) ───
CHECKSUM_FILE="$SCRIPT_DIR/checksums.sha256"
if [[ -f "$CHECKSUM_FILE" ]]; then
    echo "Verifying file integrity..."
    if (cd "$SCRIPT_DIR" && shasum -a 256 -c "$CHECKSUM_FILE" --quiet 2>/dev/null); then
        ok "All checksums verified"
    else
        fail "Checksum verification failed — files may have been tampered with"
        echo "  Run 'shasum -a 256 -c checksums.sha256' in the repo root for details." >&2
        exit 1
    fi
    echo ""
else
    info "No checksums.sha256 found — skipping integrity check"
    echo ""
fi

# ─── Install scripts ───
echo "Installing scripts..."
mkdir -p "$CLAUDE_DIR/scripts"
for script in "$SCRIPT_DIR"/scripts/*.sh; do
    cp "$script" "$CLAUDE_DIR/scripts/"
    chmod +x "$CLAUDE_DIR/scripts/$(basename "$script")"
    ok "$(basename "$script")"
done

# ─── Clean up legacy (pre-v0.7) unprefixed commands ───
# Keep in sync with uninstall.sh LEGACY_COMMANDS
LEGACY_COMMANDS=(ask-codex ask-gemini code-review multi-review research ui-design ui-review)
legacy_removed=0
for cmd in "${LEGACY_COMMANDS[@]}"; do
    target="$CLAUDE_DIR/commands/$cmd.md"
    if [[ -f "$target" ]]; then
        rm "$target"
        info "Removed legacy /$cmd (replaced by /pi-$cmd)"
        legacy_removed=$((legacy_removed + 1))
    fi
done
if [[ $legacy_removed -gt 0 ]]; then
    ok "Cleaned up $legacy_removed legacy command(s)"
    echo ""
fi

# ─── Install commands ───
echo ""
echo "Installing commands..."
mkdir -p "$CLAUDE_DIR/commands"
for cmd in "$SCRIPT_DIR"/commands/*.md; do
    cp "$cmd" "$CLAUDE_DIR/commands/"
    ok "/$(basename "$cmd" .md)"
done

# ─── Create log directory ───
mkdir -p "$CLAUDE_DIR/logs"

echo ""
echo "─────────────────────────────────────────"
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Available commands in Claude Code:"
echo "  /pi-ask-codex     — Ask Codex a question"
echo "  /pi-ask-gemini    — Ask Gemini a question"
echo "  /pi-code-review   — Cross-provider code review via Codex"
echo "  /pi-ui-design     — HTML mockup from design spec via Gemini"
echo "  /pi-ui-review     — UI/UX review via Gemini"
echo "  /pi-research      — Technical research via Gemini"
echo "  /pi-multi-review  — Triple-provider adversarial review (with smart routing)"
echo "  /pi-plan          — Generate structured implementation plan"
echo ""
echo "Utilities:"
echo "  usage-summary    — View API usage stats (today/--week/--all)"
echo "  review-insights  — Analyze recurring issues from review history"
echo "                     Run: ~/.claude/scripts/usage-summary.sh"
echo "                          ~/.claude/scripts/review-insights.sh"
echo ""
echo "Logs: $CLAUDE_DIR/logs/multi-ai.log"

if [[ "$PREREQ_OK" == false ]]; then
    echo ""
    warn "Some prerequisites are missing. Install them to enable all commands."
fi
echo ""
