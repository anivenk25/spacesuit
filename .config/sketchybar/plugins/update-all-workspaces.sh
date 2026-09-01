#!/opt/homebrew/bin/bash
# Update ALL workspace items in one shot — no per-item scripts needed.
# Hardened against: special chars in app names, monitor flapping, 1..N
# monitors, empty/invalid display ids, and concurrent invocations.

set -o pipefail

# ---- Serialize concurrent runs (rapid workspace switching / display events) ----
# macOS has no flock; use an atomic mkdir lock. If an update is already
# in flight, skip this one — the in-flight run reflects the latest state.
LOCK_DIR="/tmp/spacesuit-ws-update.lock.d"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  # Stale lock guard: if the lock is older than 10s, steal it.
  if [ -d "$LOCK_DIR" ]; then
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if [ "$lock_age" -ge 10 ]; then
      rmdir "$LOCK_DIR" 2>/dev/null
      mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    else
      exit 0
    fi
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

ALL_WS="1 2 3 4 5 6 7 8 9 10 A B C D E F"

FOCUSED="$FOCUSED_WORKSPACE"
[ -z "$FOCUSED" ] && FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null | head -1)

# ---- Gather state (each guarded; empty on failure) ----
ALL_WINDOWS=$(aerospace list-windows --all --format "%{workspace}|%{app-name}" 2>/dev/null)
MONITOR_COUNT=$(aerospace list-monitors 2>/dev/null | grep -c . )
[ -z "$MONITOR_COUNT" ] && MONITOR_COUNT=0

# ---- Map each workspace-id -> SketchyBar display index (appkit nsscreen id) ----
# Works for 1..N monitors. If aerospace can't tell us, we leave display unset
# for that item (SketchyBar keeps its previous value) rather than guessing and
# accidentally duplicating pills across monitors.
declare -A WS_DISPLAY
PRIMARY_DISPLAY=""

if [ "$MONITOR_COUNT" -le 1 ]; then
  PRIMARY_DISPLAY=$(aerospace list-monitors --format '%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null | head -1)
  # Validate integer
  [[ "$PRIMARY_DISPLAY" =~ ^[0-9]+$ ]] || PRIMARY_DISPLAY=1
  for w in $ALL_WS; do WS_DISPLAY[$w]="$PRIMARY_DISPLAY"; done
else
  # For each monitor, which workspaces live on it -> that monitor's display id
  while IFS='|' read -r mid appkit; do
    [ -z "$mid" ] && continue
    [[ "$appkit" =~ ^[0-9]+$ ]] || continue
    [ -z "$PRIMARY_DISPLAY" ] && PRIMARY_DISPLAY="$appkit"
    while IFS= read -r w; do
      w=$(printf '%s' "$w" | tr -d '[:space:]')
      [ -z "$w" ] && continue
      WS_DISPLAY[$w]="$appkit"
    done <<< "$(aerospace list-workspaces --monitor "$mid" 2>/dev/null)"
  done <<< "$(aerospace list-monitors --format '%{monitor-id}|%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null)"
  [[ "$PRIMARY_DISPLAY" =~ ^[0-9]+$ ]] || PRIMARY_DISPLAY=1
fi

# Return a valid display flag for an item, or empty string if unknown.
# Never emits an empty/zero display= (which would show the item on ALL
# displays and duplicate pills).
disp_flag() {
  local d="${WS_DISPLAY[$1]}"
  if [[ "$d" =~ ^[1-9][0-9]*$ ]]; then
    printf 'display=%s' "$d"
  else
    printf ''
  fi
}

# ---- Visible (non-focused but shown) workspaces, multi-monitor only ----
VISIBLE=""
if [ "$MONITOR_COUNT" -gt 1 ]; then
  VISIBLE=$(aerospace list-workspaces --monitor all --visible 2>/dev/null)
fi

# ---- Sanitize an app label fragment: drop chars that break the bar ----
# Removes control chars, quotes, backslash, percent (sketchybar format),
# pipe (our field separator), backtick, dollar. Collapses whitespace.
sanitize() {
  printf '%s' "$1" | tr -d '\r\n\t"`$\\|%' | sed 's/  */ /g; s/^ *//; s/ *$//'
}

# ---- Build per-workspace app summaries ----
declare -A WS_COUNT WS_APPS
while IFS='|' read -r ws app; do
  [ -z "$ws" ] && continue
  ws=$(printf '%s' "$ws" | tr -d '[:space:]')
  [ -z "$ws" ] && continue
  app=$(sanitize "$app")
  WS_COUNT[$ws]=$(( ${WS_COUNT[$ws]:-0} + 1 ))
  case "$app" in
    "Google Chrome") short="Chr" ;;
    "Microsoft Outlook") short="Mail" ;;
    "Microsoft Teams") short="Teams" ;;
    "Visual Studio Code") short="VSC" ;;
    Terminal) short="Term" ;;
    Ghostty) short="Term" ;;
    "Joule Desktop") short="Joule" ;;
    Finder) short="Find" ;;
    Safari) short="Sfri" ;;
    Slack) short="Slck" ;;
    "") short="" ;;
    *) short=$(printf '%s' "$app" | cut -c1-5) ;;
  esac
  if [ -n "$short" ] && [[ " ${WS_APPS[$ws]} " != *" $short "* ]]; then
    WS_APPS[$ws]="${WS_APPS[$ws]:+${WS_APPS[$ws]} }$short"
  fi
done <<< "$ALL_WINDOWS"

# Cap app list to first 3 names + "+N" overflow to keep labels compact
cap_apps() {
  local list="$1" max=3
  read -r -a arr <<< "$list"
  local n=${#arr[@]}
  if [ "$n" -le "$max" ]; then
    printf '%s' "$list"
  else
    printf '%s +%s' "${arr[*]:0:$max}" "$((n - max))"
  fi
}

# ---- Build command as an ARGV ARRAY (immune to injection / special chars) ----
ARGS=()

for sid in $ALL_WS; do
  count=${WS_COUNT[$sid]:-0}
  apps="$(cap_apps "${WS_APPS[$sid]}")"
  dflag="$(disp_flag "$sid")"

  ARGS+=( --set "space.$sid" )
  [ -n "$dflag" ] && ARGS+=( "$dflag" )

  if [ "$sid" = "$FOCUSED" ]; then
    ARGS+=(
      background.color=0xffcba6f7
      icon.color=0xff11111b
      icon.font="Hack Nerd Font:Bold:12.0"
      label.drawing=on
      label.color=0xff11111b
      label.font="Hack Nerd Font:Bold:10.0"
      label="[$count] $apps"
    )
  elif [ "$MONITOR_COUNT" -gt 1 ] && printf '%s\n' "$VISIBLE" | grep -qx "$sid"; then
    if [ "$count" -gt 0 ]; then lbl="[$count] $apps"; else lbl=""; fi
    ARGS+=(
      background.color=0xff89b4fa
      icon.color=0xff11111b
      icon.font="Hack Nerd Font:Bold:12.0"
      label.drawing=on
      label.color=0xff11111b
      label.font="Hack Nerd Font:Bold:10.0"
      label="$lbl"
    )
  elif [ "$count" -gt 0 ]; then
    ARGS+=(
      background.color=0xff313244
      icon.color=0xff94e2d5
      icon.font="Hack Nerd Font:Bold:12.0"
      label.drawing=on
      label.color=0xffa6adc8
      label.font="Hack Nerd Font:Regular:9.0"
      label="[$count] $apps"
    )
  else
    ARGS+=(
      background.color=0xff1e1e2e
      icon.color=0xff45475a
      icon.font="Hack Nerd Font:Regular:11.0"
      label.drawing=off
      label=""
    )
  fi
done

# ---- Re-target monitor labels + separators ----
# Main labels follow workspace 1's display; secondary labels follow A's.
MAIN_D="$(disp_flag 1)"
SEC_D="$(disp_flag A)"
ARGS+=( --set monitor_main )
[ -n "$MAIN_D" ] && ARGS+=( "$MAIN_D" )
ARGS+=( --set sep1 )
[ -n "$MAIN_D" ] && ARGS+=( "$MAIN_D" )
ARGS+=( --set monitor_sec )
[ -n "$SEC_D" ] && ARGS+=( "$SEC_D" )
ARGS+=( --set sep2 )
[ -n "$SEC_D" ] && ARGS+=( "$SEC_D" )

# ---- Single sketchybar call for ALL items ----
sketchybar "${ARGS[@]}" 2>/dev/null
