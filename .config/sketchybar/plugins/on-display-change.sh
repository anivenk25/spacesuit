#!/bin/bash
# Fired on SketchyBar display_change (monitor plugged/unplugged).
# Re-run the workspace updater, which re-detects the monitor layout and
# re-targets every pill's display= without a full config reload
# (a full reload during a display flap can drop items).
FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null)
sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE="$FOCUSED"
