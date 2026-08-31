#!/bin/bash
set -euo pipefail

# ============================================================================
# Spacesuit Installer
# Complete macOS tiling WM setup — AeroSpace + Kitty + SketchyBar + borders
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Paths
SPACESUIT_DIR="${SPACESUIT_DIR:-$HOME/.spacesuit}"
BACKUP_SUFFIX=".spacesuit.bak"

info()  { echo -e "${BLUE}[spacesuit]${NC} $1"; }
ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${PURPLE}${BOLD}==> $1${NC}"; }

# ============================================================================
# Pre-flight checks
# ============================================================================

preflight() {
  step "Pre-flight checks"

  # macOS version
  MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
  if [ "$MACOS_VERSION" -lt 13 ]; then
    err "macOS 13 (Ventura) or later required. You have $(sw_vers -productVersion)."
    exit 1
  fi
  ok "macOS $(sw_vers -productVersion)"

  # Architecture
  ARCH=$(uname -m)
  if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
  else
    BREW_PREFIX="/usr/local"
  fi
  ok "Architecture: $ARCH (brew prefix: $BREW_PREFIX)"

  # Xcode CLT
  if ! xcode-select -p &>/dev/null; then
    warn "Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "Press enter after Xcode CLT installation completes."
    read -r
  fi
  ok "Xcode Command Line Tools"

  # Homebrew
  if ! command -v brew &>/dev/null; then
    warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$($BREW_PREFIX/bin/brew shellenv)"
  fi
  ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
}

# ============================================================================
# Install dependencies
# ============================================================================

install_deps() {
  step "Installing dependencies"

  if [ ! -f "$SPACESUIT_DIR/Brewfile" ]; then
    err "Brewfile not found at $SPACESUIT_DIR/Brewfile"
    exit 1
  fi

  info "Running brew bundle (this may take a few minutes)..."
  brew bundle --file="$SPACESUIT_DIR/Brewfile" --no-lock --no-upgrade 2>&1 | while read -r line; do
    case "$line" in
      *"already installed"*|*"Skipping"*) ;;
      *"Installing"*|*"Pouring"*|*"Successfully"*) info "$line" ;;
    esac
  done

  ok "All dependencies installed"
}

# ============================================================================
# Symlink configs
# ============================================================================

make_symlink() {
  local src="$1"
  local dest="$2"

  # Already correct symlink
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    ok "Already linked: $dest"
    return
  fi

  # Backup existing file/dir
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local backup="${dest}${BACKUP_SUFFIX}"
    if [ -e "$backup" ]; then
      warn "Backup already exists: $backup (removing old target)"
      rm -rf "$dest"
    else
      warn "Backing up: $dest → $backup"
      mv "$dest" "$backup"
    fi
  fi

  # Create parent dir if needed
  mkdir -p "$(dirname "$dest")"

  # Create symlink
  ln -sf "$src" "$dest"
  ok "Linked: $dest → $src"
}

symlink_configs() {
  step "Symlinking configs"

  make_symlink "$SPACESUIT_DIR/.aerospace.toml" "$HOME/.aerospace.toml"
  make_symlink "$SPACESUIT_DIR/.config/sketchybar" "$HOME/.config/sketchybar"
  make_symlink "$SPACESUIT_DIR/.config/kitty" "$HOME/.config/kitty"
  make_symlink "$SPACESUIT_DIR/.config/borders" "$HOME/.config/borders"
  make_symlink "$SPACESUIT_DIR/.config/aerospace" "$HOME/.config/aerospace"
}

# ============================================================================
# macOS settings
# ============================================================================

apply_macos_settings() {
  step "Applying macOS settings"

  # Dock autohide
  if ! defaults read com.apple.dock autohide 2>/dev/null | grep -q 1; then
    defaults write com.apple.dock autohide -bool true
    ok "Dock autohide enabled"
  else
    ok "Dock autohide already enabled"
  fi

  # Disable MRU spaces (prevents workspace jumping when focusing apps)
  if ! defaults read com.apple.dock mru-spaces 2>/dev/null | grep -q 0; then
    defaults write com.apple.dock mru-spaces -bool false
    ok "MRU spaces disabled"
  else
    ok "MRU spaces already disabled"
  fi

  # Chrome window tabbing
  defaults write com.google.Chrome AppleWindowTabbingMode -string manual 2>/dev/null
  ok "Chrome window tabbing set to manual"

  # Restart Dock to apply
  killall Dock 2>/dev/null || true
  ok "Dock restarted"
}

# ============================================================================
# Start services
# ============================================================================

start_services() {
  step "Starting services"

  # SketchyBar
  if brew services list | grep sketchybar | grep -q started; then
    ok "SketchyBar already running"
  else
    brew services start felixkratz/formulae/sketchybar 2>/dev/null
    ok "SketchyBar started"
  fi

  # Borders
  if brew services list | grep borders | grep -q started; then
    ok "Borders already running"
  else
    brew services start felixkratz/formulae/borders 2>/dev/null
    ok "Borders started"
  fi

  # Ice
  if pgrep -x "Ice" &>/dev/null; then
    ok "Ice already running"
  else
    open -a Ice 2>/dev/null && ok "Ice started" || warn "Could not start Ice"
  fi
}

# ============================================================================
# Make scripts executable
# ============================================================================

fix_permissions() {
  step "Setting permissions"
  find "$SPACESUIT_DIR/.config/aerospace/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
  find "$SPACESUIT_DIR/.config/sketchybar/plugins" -name "*.sh" -exec chmod +x {} \; 2>/dev/null
  chmod +x "$SPACESUIT_DIR/.config/borders/bordersrc" 2>/dev/null
  chmod +x "$SPACESUIT_DIR/.config/sketchybar/sketchybarrc" 2>/dev/null
  ok "All scripts executable"
}

# ============================================================================
# Post-install
# ============================================================================

post_install() {
  step "Post-install"

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║           🚀 Spacesuit installed successfully!       ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}Two manual steps remaining:${NC}"
  echo ""
  echo -e "  ${YELLOW}1.${NC} Grant AeroSpace accessibility permission:"
  echo -e "     System Settings → Privacy & Security → Accessibility → AeroSpace ✓"
  echo ""
  echo -e "  ${YELLOW}2.${NC} Start AeroSpace:"
  echo -e "     ${BLUE}open -a AeroSpace${NC}"
  echo ""
  echo -e "  ${YELLOW}3.${NC} (Optional) Hide AeroSpace menu bar icon:"
  echo -e "     Cmd-drag it behind Ice divider in menu bar"
  echo ""
  echo -e "${BOLD}Keybinds cheat sheet:${NC}"
  echo ""
  echo -e "  ${PURPLE}alt-1..9, alt-0${NC}     Switch workspace 1-10"
  echo -e "  ${PURPLE}alt-a..f${NC}            Switch workspace A-F (secondary monitor)"
  echo -e "  ${PURPLE}alt-shift-1..0,a..f${NC} Move window to workspace"
  echo -e "  ${PURPLE}alt-hjkl${NC}            Focus left/down/up/right"
  echo -e "  ${PURPLE}alt-shift-hjkl${NC}      Move window left/down/up/right"
  echo -e "  ${PURPLE}alt-enter${NC}           New Kitty terminal"
  echo -e "  ${PURPLE}alt-space${NC}           Search windows/tabs/workspaces"
  echo -e "  ${PURPLE}alt-s${NC}               Toggle scratchpad terminal"
  echo -e "  ${PURPLE}alt-o then j/g/s/n${NC}  Quick launch: Jira/GitHub/Spotify/TextEdit"
  echo -e "  ${PURPLE}alt-o then 1-5${NC}      Launch top 5 most-used apps"
  echo -e "  ${PURPLE}alt-shift-;${NC}         Service mode (r=reset, f=float, t=tile all)"
  echo ""
  echo -e "Run ${BLUE}spacesuit doctor${NC} to check everything is working."
  echo -e "Run ${BLUE}spacesuit update${NC} to pull latest configs."
  echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  echo -e "${PURPLE}${BOLD}  ╔═══════════════════════════════════╗${NC}"
  echo -e "${PURPLE}${BOLD}  ║   SPACESUIT — macOS Tiling Setup  ║${NC}"
  echo -e "${PURPLE}${BOLD}  ╚═══════════════════════════════════╝${NC}"
  echo ""

  preflight
  install_deps
  fix_permissions
  symlink_configs
  apply_macos_settings
  start_services
  post_install
}

main "$@"
