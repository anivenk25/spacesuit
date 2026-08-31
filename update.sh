#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

SPACESUIT_DIR="${SPACESUIT_DIR:-$HOME/.spacesuit}"

info()  { echo -e "${BLUE}[spacesuit]${NC} $1"; }
ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
step()  { echo -e "\n${PURPLE}${BOLD}==> $1${NC}"; }

step "Updating Spacesuit"

# Pull latest configs
if [ -d "$SPACESUIT_DIR/.git" ]; then
  info "Pulling latest dotfiles..."
  git -C "$SPACESUIT_DIR" pull --rebase 2>&1 | while read -r line; do
    info "$line"
  done
  ok "Dotfiles updated to $(git -C "$SPACESUIT_DIR" rev-parse --short HEAD)"
else
  info "Not a git repo — skipping pull"
fi

# Update deps
step "Updating dependencies"
brew bundle --file="$SPACESUIT_DIR/Brewfile" --no-upgrade 2>/dev/null
ok "Dependencies up to date"

# Fix permissions
step "Fixing permissions"
find "$SPACESUIT_DIR/.config/aerospace/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
find "$SPACESUIT_DIR/.config/sketchybar/plugins" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
chmod +x "$SPACESUIT_DIR/.config/borders/bordersrc" 2>/dev/null
chmod +x "$SPACESUIT_DIR/.config/sketchybar/sketchybarrc" 2>/dev/null
ok "Permissions fixed"

# Restart services
step "Restarting services"
brew services restart felixkratz/formulae/sketchybar 2>/dev/null
ok "SketchyBar restarted"
brew services restart felixkratz/formulae/borders 2>/dev/null
ok "Borders restarted"

# Reload AeroSpace
if command -v aerospace &>/dev/null; then
  aerospace reload-config 2>/dev/null && ok "AeroSpace config reloaded" || info "AeroSpace not running"
fi

echo ""
echo -e "${GREEN}${BOLD}Spacesuit updated!${NC}"
echo ""
