#!/opt/homebrew/bin/bash
# search-all.sh — fast unified search: windows, chrome tabs, workspaces

TMPDIR_SEARCH="/tmp/aerospace-search"
mkdir -p "$TMPDIR_SEARCH"

# ---- Parallel data collection ----

# AeroSpace windows (instant)
ALL_WINDOWS=$(aerospace list-windows --all --format "%{window-id}|%{workspace}|%{app-name}|%{window-title}" 2>/dev/null)
FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)

# Chrome tabs + mapping in ONE AppleScript call (was 2 calls = 3.5s, now 1 call)
CHROME_DATA=$(osascript -e '
tell application "Google Chrome"
  set output to ""
  repeat with w in windows
    set wid to id of w
    set activeTitle to title of active tab of w
    set tabCount to count of tabs of w
    repeat with i from 1 to tabCount
      set t to tab i of w
      set output to output & wid & ":" & i & ":" & activeTitle & "|" & title of t & linefeed
    end repeat
  end repeat
  return output
end tell' 2>/dev/null) &
CHROME_PID=$!

# ---- Build items while Chrome query runs ----

items=""

# 1. AeroSpace windows
while IFS='|' read -r wid ws app title; do
  [ -z "$wid" ] && continue
  wid=$(echo "$wid" | tr -d ' ')
  ws=$(echo "$ws" | tr -d ' ')
  app=$(echo "$app" | sed 's/^ *//;s/ *$//')
  title=$(echo "$title" | sed 's/^ *//;s/ *$//')
  marker=""
  [ "$ws" = "$FOCUSED_WS" ] && marker="*"
  items="${items}win:${wid} | [${ws}${marker}] ${app} - ${title}
"
done <<< "$ALL_WINDOWS"

# 2. Workspaces — build from already-fetched window data (no extra calls)
declare -A WS_COUNTS WS_APPS
while IFS='|' read -r wid ws app title; do
  [ -z "$ws" ] && continue
  ws=$(echo "$ws" | tr -d ' ')
  app=$(echo "$app" | sed 's/^ *//;s/ *$//')
  WS_COUNTS[$ws]=$(( ${WS_COUNTS[$ws]:-0} + 1 ))
  if [ -n "$app" ] && [[ "${WS_APPS[$ws]}" != *"$app"* ]]; then
    WS_APPS[$ws]="${WS_APPS[$ws]:+${WS_APPS[$ws]}, }$app"
  fi
done <<< "$ALL_WINDOWS"

for ws in $(aerospace list-workspaces --all 2>/dev/null); do
  count=${WS_COUNTS[$ws]:-0}
  if [ "$count" -gt 0 ]; then
    items="${items}ws:${ws} | Workspace ${ws} (${count} windows: ${WS_APPS[$ws]})
"
  else
    items="${items}ws:${ws} | Workspace ${ws} (empty)
"
  fi
done

# ---- Wait for Chrome data ----
wait $CHROME_PID 2>/dev/null

# Build Chrome window → AeroSpace window map
CHROME_WINDOWS=$(echo "$ALL_WINDOWS" | grep -i chrome)
declare -A CHROME_MAP

while IFS='|' read -r chrome_ref tab_title; do
  [ -z "$chrome_ref" ] && continue
  chrome_wid=$(echo "$chrome_ref" | cut -d: -f1)
  active_title=$(echo "$chrome_ref" | cut -d: -f3-)
  
  # Map Chrome window to AeroSpace window (only once per Chrome window)
  if [ -z "${CHROME_MAP[$chrome_wid]}" ]; then
    while IFS='|' read -r awid aws aapp atitle; do
      awid=$(echo "$awid" | tr -d ' ')
      aws=$(echo "$aws" | tr -d ' ')
      if echo "$atitle" | grep -qF "$active_title"; then
        CHROME_MAP[$chrome_wid]="$awid|$aws"
        break
      fi
    done <<< "$CHROME_WINDOWS"
  fi

  tab_idx=$(echo "$chrome_ref" | cut -d: -f2)
  tab_title=$(echo "$tab_title" | sed 's/^ *//;s/ *$//')
  
  mapped="${CHROME_MAP[$chrome_wid]}"
  aero_wid=$(echo "$mapped" | cut -d'|' -f1)
  ws=$(echo "$mapped" | cut -d'|' -f2)
  ws_marker=""
  [ "$ws" = "$FOCUSED_WS" ] && ws_marker="*"
  
  if [ -n "$aero_wid" ]; then
    items="${items}tab:${chrome_wid}:${tab_idx}:${aero_wid} | [${ws}${ws_marker}] Chrome Tab - ${tab_title}
"
  else
    items="${items}tab:${chrome_wid}:${tab_idx}: | Chrome Tab - ${tab_title}
"
  fi
done <<< "$CHROME_DATA"

# ---- Show picker ----
selected=$(echo "$items" | grep -v '^$' | choose)
[ -z "$selected" ] && exit 0

# ---- Act on selection ----
prefix=$(echo "$selected" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')
type=$(echo "$prefix" | cut -d: -f1)

case "$type" in
  win)
    wid=$(echo "$prefix" | cut -d: -f2)
    aerospace focus --window-id "$wid" 2>/dev/null
    ;;
  tab)
    chrome_wid=$(echo "$prefix" | cut -d: -f2)
    tab_idx=$(echo "$prefix" | cut -d: -f3)
    aero_wid=$(echo "$prefix" | cut -d: -f4)
    if [ -n "$aero_wid" ]; then
      aerospace focus --window-id "$aero_wid" 2>/dev/null
    fi
    osascript -e "
      tell application \"Google Chrome\"
        repeat with w in windows
          if id of w is $chrome_wid then
            set active tab index of w to $tab_idx
          end if
        end repeat
      end tell" 2>/dev/null
    ;;
  ws)
    ws_name=$(echo "$prefix" | cut -d: -f2)
    aerospace workspace "$ws_name" 2>/dev/null
    ;;
esac

~/.config/aerospace/scripts/refresh-bar.sh
