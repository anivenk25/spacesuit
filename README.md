# Spacesuit

Complete macOS tiling window manager setup in one command.

AeroSpace + Kitty + SketchyBar + JankyBorders — Catppuccin Mocha themed.

## Install

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/anivenk25/spacesuit/main/install.sh | bash
```

### Homebrew

```bash
brew trust anivenk25/spacesuit
brew tap anivenk25/spacesuit
brew install spacesuit
spacesuit install
```

## What you get

| Component | Purpose |
|---|---|
| **AeroSpace** | i3-like tiling window manager |
| **Kitty** | GPU-accelerated terminal with proper tabs |
| **SketchyBar** | Workspace status bar (bottom) |
| **JankyBorders** | Subtle window border highlights |

### 16 workspaces across 2 monitors
- Main: 1-10
- Secondary: A-F
- Single monitor mode available during install

### Keybinds

| Bind | Action |
|---|---|
| `alt-1..9, alt-0` | Switch workspace 1-10 |
| `alt-a..f` | Switch workspace A-F |
| `alt-shift-<key>` | Move window to workspace |
| `alt-hjkl` | Focus direction |
| `alt-shift-hjkl` | Move window |
| `alt-enter` | New terminal |
| `alt-space` | Search windows + Chrome tabs |
| `alt-s` | Toggle scratchpad terminal |
| `alt-o` then `1-5` | Launch top 5 most-used apps |
| `alt-shift-;` | Service mode |

### Adaptive launcher
Tracks app usage and surfaces your most-used apps in the status bar. Press `alt-o` then `1-5` to launch them.

### Workspace search
`alt-space` opens a fuzzy finder with all windows, Chrome tabs, and workspaces. Select to focus.

### Scratchpad terminal
`alt-s` toggles a floating terminal overlay that follows you across workspaces.

## Commands

```bash
spacesuit install     # Full install (idempotent, safe to re-run)
spacesuit update      # Pull latest configs + restart services
spacesuit uninstall   # Remove symlinks, restore backups
spacesuit status      # Show symlinks, services, workspaces
spacesuit doctor      # Check for issues
```

## Uninstall

```bash
spacesuit uninstall
brew uninstall spacesuit
brew untap anivenk25/spacesuit
```

## Theme

Catppuccin Mocha across all components:
- Kitty terminal
- SketchyBar status bar
- Window borders

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel Mac
- Homebrew (installed automatically if missing)

## Credits

Built with [AeroSpace](https://github.com/nikitabobko/AeroSpace), [SketchyBar](https://github.com/FelixKratz/SketchyBar), [JankyBorders](https://github.com/FelixKratz/JankyBorders), [Kitty](https://sw.kovidgoyal.net/kitty/), [Catppuccin](https://github.com/catppuccin).
