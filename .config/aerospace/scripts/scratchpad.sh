#!/bin/bash
# Toggle scratchpad terminal
# If scratchpad exists on hidden workspace Z, bring it to current workspace
# If it's on current workspace, send it to Z
# If it doesn't exist, create it

SCRATCH_WS="Z"
CURRENT_WS=$(aerospace list-workspaces --focused 2>/dev/null)

# Find scratchpad window (kitty window with title containing "scratchpad")
SCRATCH_WID=$(aerospace list-windows --all --format "%{window-id}|%{workspace}|%{window-title}" 2>/dev/null \
  | grep "scratchpad" \
  | head -1)

if [ -z "$SCRATCH_WID" ]; then
  # No scratchpad exists — create one
  open -n -a /Applications/kitty.app --args \
    --title "scratchpad" \
    --override "background_opacity=0.9" \
    --override "font_size=12"
  
  # Wait for it to appear
  sleep 0.5
  
  # Find the new window and float it
  NEW_WID=$(aerospace list-windows --all --format "%{window-id}|%{window-title}" 2>/dev/null \
    | grep "scratchpad" \
    | head -1 \
    | cut -d'|' -f1 | tr -d ' ')
  
  if [ -n "$NEW_WID" ]; then
    aerospace layout --window-id "$NEW_WID" floating 2>/dev/null
  fi
else
  WID=$(echo "$SCRATCH_WID" | cut -d'|' -f1 | tr -d ' ')
  WS=$(echo "$SCRATCH_WID" | cut -d'|' -f2 | tr -d ' ')
  
  if [ "$WS" = "$CURRENT_WS" ]; then
    # On current workspace — hide it to Z
    aerospace move-node-to-workspace --window-id "$WID" "$SCRATCH_WS" 2>/dev/null
  else
    # Hidden — bring it here and focus
    aerospace move-node-to-workspace --window-id "$WID" "$CURRENT_WS" 2>/dev/null
    aerospace focus --window-id "$WID" 2>/dev/null
  fi
fi
