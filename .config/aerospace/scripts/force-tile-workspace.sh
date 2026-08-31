#!/bin/bash
# Force tile all windows on the focused workspace
WS=$(aerospace list-workspaces --focused 2>/dev/null)
[ -z "$WS" ] && exit 0

for wid in $(aerospace list-windows --workspace "$WS" --format "%{window-id}" 2>/dev/null); do
  aerospace layout --window-id "$wid" tiling 2>/dev/null
done

# Also flatten to reset any messy nesting
aerospace flatten-workspace-tree --workspace "$WS" 2>/dev/null
