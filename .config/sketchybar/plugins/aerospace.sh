#!/bin/bash

SID="$1"

FOCUSED="$FOCUSED_WORKSPACE"
if [ -z "$FOCUSED" ]; then
  FOCUSED="$AEROSPACE_FOCUSED_WORKSPACE"
fi

WIN_COUNT=$(aerospace list-windows --workspace "$SID" 2>/dev/null | wc -l | tr -d ' ')

IS_VISIBLE=false
for ws in $(aerospace list-workspaces --monitor all --visible 2>/dev/null); do
  if [ "$ws" = "$SID" ]; then
    IS_VISIBLE=true
  fi
done

APPS=""
if [ "$WIN_COUNT" -gt 0 ]; then
  APPS=$(aerospace list-windows --workspace "$SID" --format "%{app-name}" 2>/dev/null \
    | sort -u | head -3 \
    | sed 's/Google Chrome/Chr/;s/Microsoft Outlook/Mail/;s/Microsoft Teams/Teams/;s/Visual Studio Code/VSC/;s/Ghostty/Term/;s/kitty/Term/;s/Joule Desktop/Joule/;s/Finder/Find/;s/Safari/Sfri/;s/Slack/Slck/' \
    | cut -c1-6 \
    | tr '\n' ' ' \
    | sed 's/ $//')
fi

if [ "$SID" = "$FOCUSED" ]; then
  # FOCUSED — bright mauve bg, bold
  LABEL="[$WIN_COUNT] $APPS"
  sketchybar --set "$NAME" \
    background.color=0xffcba6f7 \
    icon.color=0xff11111b \
    icon.font="Hack Nerd Font:Bold:12.0" \
    label.drawing=on \
    label.color=0xff11111b \
    label.font="Hack Nerd Font:Bold:10.0" \
    label="$LABEL"

elif [ "$IS_VISIBLE" = true ]; then
  # VISIBLE on other monitor — blue bg
  if [ "$WIN_COUNT" -gt 0 ]; then
    LABEL="[$WIN_COUNT] $APPS"
  else
    LABEL=""
  fi
  sketchybar --set "$NAME" \
    background.color=0xff89b4fa \
    icon.color=0xff11111b \
    icon.font="Hack Nerd Font:Bold:12.0" \
    label.drawing=on \
    label.color=0xff11111b \
    label.font="Hack Nerd Font:Bold:10.0" \
    label="$LABEL"

elif [ "$WIN_COUNT" -gt 0 ]; then
  # HAS WINDOWS — teal text, visible
  LABEL="[$WIN_COUNT] $APPS"
  sketchybar --set "$NAME" \
    background.color=0xff313244 \
    icon.color=0xff94e2d5 \
    icon.font="Hack Nerd Font:Bold:12.0" \
    label.drawing=on \
    label.color=0xffa6adc8 \
    label.font="Hack Nerd Font:Regular:9.0" \
    label="$LABEL"

else
  # EMPTY — dim overlay
  sketchybar --set "$NAME" \
    background.color=0xff1e1e2e \
    icon.color=0xff45475a \
    icon.font="Hack Nerd Font:Regular:11.0" \
    label.drawing=off \
    label=""
fi
