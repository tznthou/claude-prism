#!/usr/bin/env bash
# uninstall.sh — Remove claude-prism commands and scripts

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }

# Keep in sync with install.sh LEGACY_COMMANDS
LEGACY_COMMANDS=(ask-codex ask-gemini code-review multi-review research ui-design ui-review)
SCRIPTS=(call-codex.sh call-gemini.sh detect-domain.sh)

echo ""
echo "Uninstalling claude-prism..."
echo ""

# Dynamically discover installed pi-* commands (avoids hardcoded list drift)
echo "Removing commands..."
removed=0
for target in "$CLAUDE_DIR"/commands/pi-*.md; do
    [[ -f "$target" ]] || continue
    name="$(basename "$target" .md)"
    rm "$target"
    ok "Removed /$name"
    removed=$((removed + 1))
done
[[ $removed -eq 0 ]] && warn "No pi-* commands found"

# Clean up legacy (pre-v0.7) unprefixed commands if present
for cmd in "${LEGACY_COMMANDS[@]}"; do
    target="$CLAUDE_DIR/commands/$cmd.md"
    if [[ -f "$target" ]]; then
        rm "$target"
        ok "Removed legacy /$cmd"
    fi
done

echo ""
echo "Removing scripts..."
for script in "${SCRIPTS[@]}"; do
    target="$CLAUDE_DIR/scripts/$script"
    if [[ -f "$target" ]]; then
        rm "$target"
        ok "Removed $script"
    else
        warn "$script not found (skipped)"
    fi
done

echo ""
echo -e "${GREEN}Uninstall complete.${NC}"
echo ""
echo "Note: Log file at $CLAUDE_DIR/logs/multi-ai.log was preserved."
echo "      Delete manually if no longer needed."
echo ""
