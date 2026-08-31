#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

BACKUP_SUFFIX=".spacesuit.bak"

info()  { echo -e "${BLUE}[spacesuit]${NC} $1"; }
ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${PURPLE}${BOLD}==> $1${NC}"; }

echo ""
echo -e "${RED}${BOLD}  ╔═══════════════════════════════════╗${NC}"
echo -e "${RED}${BOLD}  ║   SPACESUIT — Uninstall            ║${NC}"
echo -e "${RED}${BOLD}  ╚═══════════════════════════════════╝${NC}"
echo ""

# Confirm
echo -e "${YELLOW}This will remove Spacesuit symlinks and restore backups.${NC}"
echo -e "${YELLOW}Brew packages will NOT be uninstalled.${NC}"
echo ""
read -rp "Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
  echo "Cancelled."
  exit 0
fi

# Stop services
step "Stopping services"
brew services stop felixkratz/formulae/sketchybar 2>/dev/null && ok "SketchyBar stopped" || info "SketchyBar not running"
brew services stop felixkratz/formulae/borders 2>/dev/null && ok "Borders stopped" || info "Borders not running"

# Remove symlinks and restore backups
step "Removing symlinks"

restore_backup() {
  local target="$1"
  local backup="${target}${BACKUP_SUFFIX}"

  if [ -L "$target" ]; then
    rm "$target"
    ok "Removed symlink: $target"

    if [ -e "$backup" ]; then
      mv "$backup" "$target"
      ok "Restored backup: $backup → $target"
    fi
  elif [ -e "$target" ]; then
    warn "Not a symlink, skipping: $target"
  else
    info "Not found, skipping: $target"
  fi
}

restore_backup "$HOME/.aerospace.toml"
restore_backup "$HOME/.config/sketchybar"
restore_backup "$HOME/.config/kitty"
restore_backup "$HOME/.config/borders"
restore_backup "$HOME/.config/aerospace"

# Restore Dock settings
step "Restoring macOS settings"
defaults write com.apple.dock mru-spaces -bool true 2>/dev/null
defaults delete com.apple.dock autohide 2>/dev/null || true
killall Dock 2>/dev/null || true
ok "Dock settings restored"

echo ""
echo -e "${GREEN}${BOLD}Spacesuit uninstalled.${NC}"
echo ""
echo -e "Brew packages were kept. To remove them:"
echo -e "  ${BLUE}brew uninstall aerospace sketchybar borders kitty ice fzf choose-gui bash${NC}"
echo -e "  ${BLUE}brew uninstall --cask sf-symbols font-hack-nerd-font${NC}"
echo ""
echo -e "To remove Spacesuit source:"
echo -e "  ${BLUE}rm -rf ~/.spacesuit${NC}"
echo ""
