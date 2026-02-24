#!/usr/bin/env bash
# install.sh — Install claude-code-multi-ai commands and scripts
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
echo "║   claude-code-multi-ai installer         ║"
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
        warn "Gemini CLI not found — /ask-gemini, /ui-review, /research will not work"
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
        warn "Codex CLI not found — /ask-codex, /code-review will not work"
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

# ─── Backup existing files ───
BACKUP_DIR="$CLAUDE_DIR/.multi-ai-backup-$(date +%Y%m%d%H%M%S)"
NEEDS_BACKUP=false

for cmd in "$SCRIPT_DIR"/commands/*.md; do
    target="$CLAUDE_DIR/commands/$(basename "$cmd")"
    if [[ -f "$target" ]]; then
        NEEDS_BACKUP=true
        break
    fi
done

for script in "$SCRIPT_DIR"/scripts/*.sh; do
    target="$CLAUDE_DIR/scripts/$(basename "$script")"
    if [[ -f "$target" ]]; then
        NEEDS_BACKUP=true
        break
    fi
done

if [[ "$NEEDS_BACKUP" == true ]]; then
    mkdir -p "$BACKUP_DIR/commands" "$BACKUP_DIR/scripts"
    for cmd in "$SCRIPT_DIR"/commands/*.md; do
        target="$CLAUDE_DIR/commands/$(basename "$cmd")"
        [[ -f "$target" ]] && cp "$target" "$BACKUP_DIR/commands/"
    done
    for script in "$SCRIPT_DIR"/scripts/*.sh; do
        target="$CLAUDE_DIR/scripts/$(basename "$script")"
        [[ -f "$target" ]] && cp "$target" "$BACKUP_DIR/scripts/"
    done
    info "Existing files backed up to $BACKUP_DIR"
fi

# ─── Install scripts ───
echo "Installing scripts..."
mkdir -p "$CLAUDE_DIR/scripts"
for script in "$SCRIPT_DIR"/scripts/*.sh; do
    cp "$script" "$CLAUDE_DIR/scripts/"
    chmod +x "$CLAUDE_DIR/scripts/$(basename "$script")"
    ok "$(basename "$script")"
done

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
echo "  /ask-codex      — Ask Codex (GPT-5.3) a question"
echo "  /ask-gemini     — Ask Gemini (3 Pro) a question"
echo "  /code-review    — Cross-provider code review via Codex"
echo "  /ui-review      — UI/UX review via Gemini"
echo "  /research       — Technical research via Gemini"
echo "  /multi-review   — Triple-provider adversarial review"
echo ""
echo "Logs: $CLAUDE_DIR/logs/multi-ai.log"

if [[ "$PREREQ_OK" == false ]]; then
    echo ""
    warn "Some prerequisites are missing. Install them to enable all commands."
fi
echo ""
