#!/opt/homebrew/bin/bash
# Update ALL workspace items in one shot — no per-item scripts needed.
# Renders each workspace's REAL app icons as a composited strip PNG.
# Hardened against: special chars/injection, monitor flapping, 1..N monitors,
# empty/invalid display ids, concurrent invocations, and overflow.

set -o pipefail

CONFIG_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$CONFIG_DIR_SELF/icon-helpers.sh"

# ---- Serialize concurrent runs (rapid workspace switching / display events) ----
# macOS has no flock; use an atomic mkdir lock. If an update is in flight, skip.
LOCK_DIR="/tmp/spacesuit-ws-update.lock.d"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [ -d "$LOCK_DIR" ]; then
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if [ "$lock_age" -ge 10 ]; then
      rmdir "$LOCK_DIR" 2>/dev/null; mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    else
      exit 0
    fi
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

ALL_WS="1 2 3 4 5 6 7 8 9 10 A B C D E F"
ICON_CAP="${SPACESUIT_ICON_CAP:-4}"   # max icons per pill before "+N"

# Layout tunables (px).
# GAP: per-side outer padding between items. Visible gap = 2*GAP.
SPACESUIT_GAP="${SPACESUIT_GAP:-5}"
# EMPTY_W: fixed item width for empty (no-app) workspace pills.
SPACESUIT_EMPTY_W="${SPACESUIT_EMPTY_W:-28}"

FOCUSED="$FOCUSED_WORKSPACE"
[ -z "$FOCUSED" ] && FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null | head -1)

# ---- Gather state (minimize aerospace calls) ----
ALL_WINDOWS=$(aerospace list-windows --all --format "%{workspace}|%{app-bundle-id}" 2>/dev/null)
MONITOR_DATA=$(aerospace list-monitors --format '%{monitor-id}|%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null)
MONITOR_COUNT=$(printf '%s\n' "$MONITOR_DATA" | grep -c .)
[ -z "$MONITOR_COUNT" ] && MONITOR_COUNT=0

# ---- Map each workspace-id -> SketchyBar display index (appkit nsscreen id) ----
declare -A WS_DISPLAY
if [ "$MONITOR_COUNT" -le 1 ]; then
  PRIMARY_DISPLAY="${MONITOR_DATA##*|}"
  [[ "$PRIMARY_DISPLAY" =~ ^[0-9]+$ ]] || PRIMARY_DISPLAY=1
  for w in $ALL_WS; do WS_DISPLAY[$w]="$PRIMARY_DISPLAY"; done
else
  while IFS='|' read -r mid appkit; do
    [ -z "$mid" ] && continue
    [[ "$appkit" =~ ^[0-9]+$ ]] || continue
    while IFS= read -r w; do
      w="${w// /}"
      [ -z "$w" ] && continue
      WS_DISPLAY[$w]="$appkit"
    done <<< "$(aerospace list-workspaces --monitor "$mid" 2>/dev/null)"
  done <<< "$MONITOR_DATA"
fi

# Inline display flag (avoid function call + subshell per workspace).
# Populated in the loop below using WS_DISPLAY directly.

# ---- Visible (non-focused but shown) workspaces, multi-monitor only ----
declare -A VISIBLE_MAP
if [ "$MONITOR_COUNT" -gt 1 ]; then
  while IFS= read -r _vw; do
    _vw="${_vw// /}"
    [ -n "$_vw" ] && VISIBLE_MAP[$_vw]=1
  done <<< "$(aerospace list-workspaces --monitor all --visible 2>/dev/null)"
fi

# ---- Build per-workspace unique bundle-id lists (first-seen order) ----
declare -A WS_BIDS WS_COUNT
while IFS='|' read -r ws bid; do
  [ -z "$ws" ] && continue
  ws="${ws// /}"
  [ -z "$ws" ] && continue
  bid="${bid// /}"
  WS_COUNT[$ws]=$(( ${WS_COUNT[$ws]:-0} + 1 ))
  [ -z "$bid" ] && continue
  if [[ " ${WS_BIDS[$ws]} " != *" $bid "* ]]; then
    WS_BIDS[$ws]="${WS_BIDS[$ws]:+${WS_BIDS[$ws]} }$bid"
  fi
done <<< "$ALL_WINDOWS"

# ---- Build command as ARGV ARRAY (injection-proof) ----
ARGS=()

for sid in $ALL_WS; do
  wincount=${WS_COUNT[$sid]:-0}
  read -r -a bids <<< "${WS_BIDS[$sid]}"
  nbids=${#bids[@]}

  # Inline display flag (no subshell)
  _d="${WS_DISPLAY[$sid]}"
  dflag=""
  [[ "$_d" =~ ^[1-9][0-9]*$ ]] && dflag="display=$_d"

  # Focused pill uses a dark baked number (light number is unreadable on mauve).
  focus_flag=0
  [ "$sid" = "$FOCUSED" ] && focus_flag=1

  # Build icon strip (number baked in + capped icons) + overflow label.
  # build_strip echoes "path|pixel_width"; parse both.
  strip=""
  strip_px=0
  overflow_label=""
  if [ "$nbids" -gt 0 ]; then
    strip_out="$(build_strip "$sid" "$focus_flag" "$ICON_CAP" "${bids[@]}")"
    strip="${strip_out%%|*}"
    strip_px="${strip_out##*|}"
    [[ "$strip_px" =~ ^[0-9]+$ ]] || strip_px=0
    if [ "$nbids" -gt "$ICON_CAP" ]; then
      overflow_label="+$((nbids - ICON_CAP))"
    fi
  fi

  ARGS+=( --set "space.$sid" )
  [ -n "$dflag" ] && ARGS+=( "$dflag" )

  # Tight inter-pill gap. No background inset — fill spans the full item box.
  ARGS+=(
    padding_left="$SPACESUIT_GAP" padding_right="$SPACESUIT_GAP"
    background.padding_left=0 background.padding_right=0
  )

  # State background color + border.
  #   focused -> solid mauve (with soft matching border glow)
  #   visible -> solid blue
  #   occupied-> translucent surface (reads as "has apps" without shouting)
  #   empty   -> nearly transparent chip with a faint hairline outline
  if [ "$sid" = "$FOCUSED" ]; then
    ARGS+=( background.color=0xffcba6f7 background.border_color=0xfff5c2e7 background.border_width=2 )
  elif [ "$MONITOR_COUNT" -gt 1 ] && [ "${VISIBLE_MAP[$sid]}" = "1" ]; then
    ARGS+=( background.color=0xff89b4fa background.border_width=0 )
  elif [ "$wincount" -gt 0 ]; then
    ARGS+=( background.color=0xff313244 background.border_color=0xff45475a background.border_width=1 )
  else
    ARGS+=( background.color=0xff181825 background.border_color=0xff313244 background.border_width=1 )
  fi

  if [ -n "$strip" ] && [ -f "$strip" ]; then
    # Populated pill: tight fit. pill_w = strip display width (the strip already
    # has symmetric STRIP_EDGE margins baked in). Left-aligned is fine here.
    pill_w=$(( strip_px / 2 ))
    [ "$pill_w" -lt 24 ] && pill_w=24
    [ -n "$overflow_label" ] && pill_w=$(( pill_w + 18 ))
    ARGS+=(
      icon.drawing=off icon=""
      icon.padding_left=0 icon.padding_right=0
      icon.width=0
      icon.background.image.drawing=off icon.background.drawing=off
      label.padding_left=0 label.padding_right=0
      width="$pill_w"
      background.image="$strip"
      background.image.drawing=on
      background.image.scale=0.5
    )
  else
    # Empty pill: centered digit. Set icon.width = item width so
    # icon.align=center has a full-width box to center the glyph in.
    ARGS+=(
      width="$SPACESUIT_EMPTY_W"
      background.image.drawing=off
      icon.background.image.drawing=off
      icon.background.drawing=off
      icon.drawing=on icon="$sid"
      icon.width="$SPACESUIT_EMPTY_W"
      icon.align=center
      icon.padding_left=0 icon.padding_right=0
      label.drawing=off
      label.padding_left=0 label.padding_right=0
    )
    if [ "$sid" = "$FOCUSED" ]; then
      ARGS+=( icon.color=0xff11111b icon.font="Hack Nerd Font:Bold:14.0" )
    else
      ARGS+=( icon.color=0xff6c7086 icon.font="Hack Nerd Font:Bold:13.0" )
    fi
  fi

  # Overflow "+N" as the label (only when apps exceed the icon cap)
  if [ -n "$overflow_label" ]; then
    ARGS+=(
      label="$overflow_label"
      label.drawing=on
      label.font="Hack Nerd Font:Bold:9.0"
      label.color=0xffa6adc8
    )
  else
    ARGS+=( label.drawing=off label="" )
  fi
done

# ---- Re-target monitor labels + separators (inline, no subshell) ----
_md="${WS_DISPLAY[1]}"; MAIN_D=""; [[ "$_md" =~ ^[1-9][0-9]*$ ]] && MAIN_D="display=$_md"
_sd="${WS_DISPLAY[A]}"; SEC_D="";  [[ "$_sd" =~ ^[1-9][0-9]*$ ]] && SEC_D="display=$_sd"
ARGS+=( --set monitor_main ); [ -n "$MAIN_D" ] && ARGS+=( "$MAIN_D" )
ARGS+=( --set sep1 );        [ -n "$MAIN_D" ] && ARGS+=( "$MAIN_D" )
ARGS+=( --set monitor_sec ); [ -n "$SEC_D" ]  && ARGS+=( "$SEC_D" )
ARGS+=( --set sep2 );        [ -n "$SEC_D" ]  && ARGS+=( "$SEC_D" )

# ---- Single sketchybar call for ALL items ----
sketchybar "${ARGS[@]}" 2>/dev/null
