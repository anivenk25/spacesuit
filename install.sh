#!/bin/bash
set -euo pipefail

# ============================================================================
# Spacesuit Installer
# Complete macOS tiling WM setup — AeroSpace + Kitty + SketchyBar + borders
# https://github.com/anivenk25/spacesuit
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
# Clone repo (for curl install path)
# ============================================================================

clone_repo() {
  if [ -d "$SPACESUIT_DIR/.git" ]; then
    info "Spacesuit repo already exists at $SPACESUIT_DIR"
    info "Pulling latest..."
    git -C "$SPACESUIT_DIR" pull --rebase 2>/dev/null || true
    ok "Repo up to date"
  elif [ -d "$SPACESUIT_DIR" ] && [ -f "$SPACESUIT_DIR/spacesuit" ]; then
    # Installed via brew formula — SPACESUIT_DIR is libexec, not a git repo
    ok "Using brew-installed spacesuit at $SPACESUIT_DIR"
  else
    info "Cloning spacesuit to $SPACESUIT_DIR..."
    git clone https://github.com/anivenk25/spacesuit.git "$SPACESUIT_DIR" 2>&1
    ok "Cloned to $SPACESUIT_DIR"
  fi
}

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
    echo ""
    echo -e "${YELLOW}Press enter after Xcode CLT installation completes.${NC}"
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
# Monitor setup
# ============================================================================

monitor_setup() {
  step "Monitor configuration"

  # Non-interactive mode (e.g. piped from brew post_install)
  if [ ! -t 0 ]; then
    # Auto-detect: check how many monitors are connected
    if command -v aerospace &>/dev/null && aerospace list-monitors &>/dev/null 2>&1; then
      MON_COUNT=$(aerospace list-monitors 2>/dev/null | wc -l | tr -d ' ')
      if [ "$MON_COUNT" -gt 1 ]; then
        info "Detected $MON_COUNT monitors — using dual monitor config"
        ok "Dual monitor configured"
      else
        info "Detected 1 monitor — keeping dual config (works on single too)"
        ok "Config ready (works with 1 or 2 monitors)"
      fi
    else
      info "AeroSpace not running — keeping default dual monitor config"
      ok "Config ready"
    fi
    return
  fi

  echo ""
  echo -e "  ${BOLD}How many monitors do you use?${NC}"
  echo ""
  echo -e "  ${BLUE}1)${NC} Single monitor (all 16 workspaces on one screen)"
  echo -e "  ${BLUE}2)${NC} Dual monitors (1-10 on main, A-F on secondary) ${GREEN}[default]${NC}"
  echo -e "  ${BLUE}3)${NC} Skip (configure manually later)"
  echo ""

  while true; do
    read -rp "  Enter choice [1-3] (default: 2): " choice
    choice="${choice:-2}"
    case "$choice" in
      1)
        info "Configuring for single monitor..."
        if [ -f "$SPACESUIT_DIR/.aerospace.toml" ]; then
          sed -i '' '/^\[workspace-to-monitor-force-assignment\]/,/^$/c\
# workspace-to-monitor-force-assignment not set — all workspaces on single monitor\
' "$SPACESUIT_DIR/.aerospace.toml"
        fi
        ok "Single monitor configured — all 16 workspaces on one screen"
        break
        ;;
      2)
        info "Keeping dual monitor config (1-10 main, A-F secondary)..."
        ok "Dual monitor configured"
        break
        ;;
      3)
        info "Skipping monitor setup..."
        warn "Edit ~/.aerospace.toml [workspace-to-monitor-force-assignment] section later"
        break
        ;;
      *)
        echo -e "  ${RED}Invalid choice. Enter 1, 2, or 3.${NC}"
        ;;
    esac
  done
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

  info "Running brew bundle (this may take a few minutes on first install)..."
  if brew bundle --file="$SPACESUIT_DIR/Brewfile" --no-upgrade 2>&1 | grep -v "^$" | while read -r line; do
    case "$line" in
      *"already installed"*|*"Skipping"*) ;;
      *"Using"*) ;;
      *) info "$line" ;;
    esac
  done; then
    ok "All dependencies installed"
  else
    ok "Dependencies installed (some may have been skipped)"
  fi
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
  ok "Linked: $dest"
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

  # Auto-hide menu bar (replaces Ice)
  defaults write NSGlobalDomain _HIHideMenuBar -bool true 2>/dev/null
  ok "Menu bar auto-hide enabled"

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
  if brew services list 2>/dev/null | grep sketchybar | grep -q started; then
    ok "SketchyBar already running"
  else
    brew services start felixkratz/formulae/sketchybar 2>/dev/null
    ok "SketchyBar started"
  fi

  # Borders
  if brew services list 2>/dev/null | grep borders | grep -q started; then
    ok "Borders already running"
  else
    brew services start felixkratz/formulae/borders 2>/dev/null
    ok "Borders started"
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
# Post-install — auto-open AeroSpace + accessibility settings
# ============================================================================

post_install() {
  step "Final setup"

  # Open AeroSpace
  info "Starting AeroSpace..."
  open -a AeroSpace 2>/dev/null || warn "Could not start AeroSpace — open it manually"
  sleep 1

  # Open accessibility settings
  info "Opening Accessibility settings..."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true

  echo ""
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}║          Spacesuit installed successfully!           ║${NC}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${YELLOW}${BOLD}One step remaining:${NC}"
  echo -e "  Grant AeroSpace accessibility permission in the window that just opened."
  echo -e "  Toggle ${BOLD}AeroSpace${NC} to ${GREEN}ON${NC} in the list."
  echo ""
  echo -e "  ${BOLD}Keybinds cheat sheet:${NC}"
  echo ""
  echo -e "  ${PURPLE}alt-1..9, alt-0${NC}       Switch workspace 1-10"
  echo -e "  ${PURPLE}alt-a..f${NC}              Switch workspace A-F"
  echo -e "  ${PURPLE}alt-shift-<key>${NC}       Move window to workspace"
  echo -e "  ${PURPLE}alt-hjkl${NC}              Focus left/down/up/right"
  echo -e "  ${PURPLE}alt-shift-hjkl${NC}        Move window"
  echo -e "  ${PURPLE}alt-enter${NC}             New Kitty terminal"
  echo -e "  ${PURPLE}alt-space${NC}             Search windows/tabs/workspaces"
  echo -e "  ${PURPLE}alt-s${NC}                 Toggle scratchpad terminal"
  echo -e "  ${PURPLE}alt-o then 1-5${NC}        Launch top 5 most-used apps"
  echo -e "  ${PURPLE}alt-shift-;${NC}           Service mode (r=reset, f=float, t=tile all)"
  echo ""
  echo -e "  Run ${BLUE}spacesuit doctor${NC} to verify everything is working."
  echo -e "  Run ${BLUE}spacesuit update${NC} to pull latest configs."
  echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  echo -e "${PURPLE}${BOLD}   ____                              _ _${NC}"
  echo -e "${PURPLE}${BOLD}  / ___| _ __   __ _  ___ ___  ___ _   _(_) |_${NC}"
  echo -e "${PURPLE}${BOLD}  \\___ \\| '_ \\ / _\` |/ __/ _ \\/ __| | | | | __|${NC}"
  echo -e "${PURPLE}${BOLD}   ___) | |_) | (_| | (_|  __/\\__ \\ |_| | | |_${NC}"
  echo -e "${PURPLE}${BOLD}  |____/| .__/ \\__,_|\\___\\___||___/\\__,_|_|\\__|${NC}"
  echo -e "${PURPLE}${BOLD}        |_|${NC}"
  echo ""
  echo -e "  macOS Tiling Setup"
  echo ""

  clone_repo
  preflight
  install_deps
  fix_permissions
  monitor_setup
  symlink_configs
  apply_macos_settings
  start_services
  post_install
}

main "$@"
