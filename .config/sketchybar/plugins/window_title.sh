#!/bin/bash

# Get focused window title
TITLE=$(aerospace list-windows --focused --format "%{window-title}" 2>/dev/null | head -1)

if [ -n "$TITLE" ]; then
  sketchybar --set $NAME label="$TITLE"
else
  sketchybar --set $NAME label="—"
fi
