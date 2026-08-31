#!/bin/bash
# Save current window-workspace mapping
STATE_FILE="$HOME/.config/aerospace/state.json"
mkdir -p "$(dirname "$STATE_FILE")"

aerospace list-windows --all --format "%{window-id}|%{app-bundle-id}|%{app-name}|%{window-title}|%{workspace}" 2>/dev/null \
  > "$STATE_FILE"
