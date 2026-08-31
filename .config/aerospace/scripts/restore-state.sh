#!/bin/bash
# Restore windows to their saved workspaces after AeroSpace restart
STATE_FILE="$HOME/.config/aerospace/state.json"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Wait for windows to be available
sleep 2

# Read saved state and match by app-bundle-id + window-title
while IFS='|' read -r old_wid bundle_id app_name win_title workspace; do
  [ -z "$bundle_id" ] && continue
  [ -z "$workspace" ] && continue

  # Find current window ID matching this app + title
  current_wid=$(aerospace list-windows --all --format "%{window-id}|%{app-bundle-id}|%{window-title}" 2>/dev/null \
    | grep "^[0-9]*|${bundle_id}|${win_title}$" \
    | head -1 \
    | cut -d'|' -f1)

  if [ -n "$current_wid" ]; then
    aerospace move-node-to-workspace --window-id "$current_wid" "$workspace" 2>/dev/null
  fi
done < "$STATE_FILE"

# If exact title match missed some, fall back to app-only match
while IFS='|' read -r old_wid bundle_id app_name win_title workspace; do
  [ -z "$bundle_id" ] && continue
  [ -z "$workspace" ] && continue

  # Check if any window of this app is still on wrong workspace
  aerospace list-windows --all --format "%{window-id}|%{app-bundle-id}|%{workspace}" 2>/dev/null \
    | grep "|${bundle_id}|" \
    | while IFS='|' read -r wid bid cur_ws; do
        if [ "$cur_ws" != "$workspace" ]; then
          # Only move if no window of this app is already on target workspace
          count=$(aerospace list-windows --workspace "$workspace" --app-bundle-id "$bundle_id" --count 2>/dev/null)
          if [ "$count" = "0" ]; then
            aerospace move-node-to-workspace --window-id "$wid" "$workspace" 2>/dev/null
            break
          fi
        fi
      done
done < "$STATE_FILE"
