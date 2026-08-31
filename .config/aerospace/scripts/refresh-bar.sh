#!/bin/bash
# Refresh all workspace items in SketchyBar
FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null)
sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE="$FOCUSED" 2>/dev/null
