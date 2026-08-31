#!/opt/homebrew/bin/bash
# Update ALL workspace items in one shot — no per-item scripts needed

FOCUSED="$FOCUSED_WORKSPACE"
[ -z "$FOCUSED" ] && FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null)

# Single call: get all windows
ALL_WINDOWS=$(aerospace list-windows --all --format "%{window-id}|%{workspace}|%{app-name}" 2>/dev/null)

# Single call: monitor count
MONITOR_COUNT=$(aerospace list-monitors 2>/dev/null | wc -l | tr -d ' ')

# Single call: visible workspaces (only if multi-monitor)
VISIBLE=""
if [ "$MONITOR_COUNT" -gt 1 ]; then
  VISIBLE=$(aerospace list-workspaces --monitor all --visible 2>/dev/null)
fi

# Build per-workspace data
declare -A WS_COUNT WS_APPS
while IFS='|' read -r wid ws app; do
  [ -z "$ws" ] && continue
  ws=$(echo "$ws" | tr -d ' ')
  app=$(echo "$app" | sed 's/^ *//;s/ *$//')
  WS_COUNT[$ws]=$(( ${WS_COUNT[$ws]:-0} + 1 ))
  # Shorten app names
  case "$app" in
    "Google Chrome") short="Chr" ;;
    "Microsoft Outlook") short="Mail" ;;
    "Microsoft Teams") short="Teams" ;;
    "Visual Studio Code") short="VSC" ;;
    kitty) short="Term" ;;
    "Joule Desktop") short="Joule" ;;
    Finder) short="Find" ;;
    Safari) short="Sfri" ;;
    Slack) short="Slck" ;;
    *) short=$(echo "$app" | cut -c1-5) ;;
  esac
  if [ -n "$short" ] && [[ "${WS_APPS[$ws]}" != *"$short"* ]]; then
    WS_APPS[$ws]="${WS_APPS[$ws]:+${WS_APPS[$ws]} }$short"
  fi
done <<< "$ALL_WINDOWS"

# Build one big sketchybar command
CMD=""

for sid in 1 2 3 4 5 6 7 8 9 10 A B C D E F; do
  count=${WS_COUNT[$sid]:-0}
  apps="${WS_APPS[$sid]}"

  if [ "$sid" = "$FOCUSED" ]; then
    label="[$count] $apps"
    CMD="$CMD --set space.$sid \
      background.color=0xffcba6f7 \
      icon.color=0xff11111b \
      icon.font=\"Hack Nerd Font:Bold:12.0\" \
      label.drawing=on \
      label.color=0xff11111b \
      label.font=\"Hack Nerd Font:Bold:10.0\" \
      label=\"$label\""

  elif [ "$MONITOR_COUNT" -gt 1 ] && echo "$VISIBLE" | grep -qx "$sid" && [ "$sid" != "$FOCUSED" ]; then
    if [ "$count" -gt 0 ]; then
      label="[$count] $apps"
    else
      label=""
    fi
    CMD="$CMD --set space.$sid \
      background.color=0xff89b4fa \
      icon.color=0xff11111b \
      icon.font=\"Hack Nerd Font:Bold:12.0\" \
      label.drawing=on \
      label.color=0xff11111b \
      label.font=\"Hack Nerd Font:Bold:10.0\" \
      label=\"$label\""

  elif [ "$count" -gt 0 ]; then
    label="[$count] $apps"
    CMD="$CMD --set space.$sid \
      background.color=0xff313244 \
      icon.color=0xff94e2d5 \
      icon.font=\"Hack Nerd Font:Bold:12.0\" \
      label.drawing=on \
      label.color=0xffa6adc8 \
      label.font=\"Hack Nerd Font:Regular:9.0\" \
      label=\"$label\""

  else
    CMD="$CMD --set space.$sid \
      background.color=0xff1e1e2e \
      icon.color=0xff45475a \
      icon.font=\"Hack Nerd Font:Regular:11.0\" \
      label.drawing=off \
      label=\"\""
  fi
done

# Single sketchybar call for ALL items
eval "sketchybar $CMD" 2>/dev/null
