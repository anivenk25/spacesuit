#!/bin/bash
# search-all.sh — unified search: windows, chrome tabs, workspaces
# Uses 'choose' for instant native macOS popup

FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)

# ---- Build Chrome window ID → AeroSpace window ID mapping ----
# Match by active tab title substring in AeroSpace window title
declare -A CHROME_MAP
while IFS='|' read -r chrome_wid chrome_title; do
  chrome_wid=$(echo "$chrome_wid" | tr -d ' ')
  chrome_title=$(echo "$chrome_title" | sed 's/^ *//;s/ *$//')
  [ -z "$chrome_wid" ] && continue
  
  # Find AeroSpace window whose title contains this Chrome tab title
  while IFS='|' read -r awid atitle; do
    awid=$(echo "$awid" | tr -d ' ')
    if echo "$atitle" | grep -qF "$chrome_title"; then
      CHROME_MAP[$chrome_wid]="$awid"
      break
    fi
  done <<< "$(aerospace list-windows --all --format "%{window-id}|%{window-title}" 2>/dev/null | grep -i chrome)"
done <<< "$(osascript -e '
tell application "Google Chrome"
  set output to ""
  repeat with w in windows
    set wid to id of w
    set t to active tab of w
    set output to output & wid & "|" & title of t & linefeed
  end repeat
  return output
end tell' 2>/dev/null)"

# ---- Collect all items ----

items=""

# 1. AeroSpace windows
while IFS= read -r line; do
  [ -z "$line" ] && continue
  wid=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')
  ws=$(echo "$line" | cut -d'|' -f2 | tr -d ' ')
  app=$(echo "$line" | cut -d'|' -f3 | sed 's/^ *//;s/ *$//')
  title=$(echo "$line" | cut -d'|' -f4- | sed 's/^ *//;s/ *$//')
  
  marker=""
  if [ "$ws" = "$FOCUSED_WS" ]; then
    marker="*"
  fi
  
  items="${items}win:${wid} | [${ws}${marker}] ${app} - ${title}
"
done <<< "$(aerospace list-windows --all --format "%{window-id}|%{workspace}|%{app-name}|%{window-title}" 2>/dev/null)"

# 2. Chrome tabs — include AeroSpace window ID for workspace mapping
chrome_tabs=$(osascript -e '
tell application "Google Chrome"
  set output to ""
  repeat with w in windows
    set wid to id of w
    set tabCount to count of tabs of w
    set activeIdx to active tab index of w
    repeat with i from 1 to tabCount
      set t to tab i of w
      if i = activeIdx then
        set marker to " [active]"
      else
        set marker to ""
      end if
      set output to output & wid & ":" & i & "|" & title of t & marker & linefeed
    end repeat
  end repeat
  return output
end tell' 2>/dev/null)

while IFS='|' read -r chrome_ref tab_title; do
  [ -z "$chrome_ref" ] && continue
  chrome_wid=$(echo "$chrome_ref" | cut -d: -f1)
  tab_idx=$(echo "$chrome_ref" | cut -d: -f2)
  tab_title=$(echo "$tab_title" | sed 's/^ *//;s/ *$//')
  
  # Get AeroSpace window ID for this Chrome window
  aero_wid="${CHROME_MAP[$chrome_wid]}"
  
  # Get workspace for this Chrome window
  if [ -n "$aero_wid" ]; then
    ws=$(aerospace list-windows --all --format "%{window-id}|%{workspace}" 2>/dev/null | grep "^${aero_wid}|" | cut -d'|' -f2 | tr -d ' ')
    ws_marker=""
    if [ "$ws" = "$FOCUSED_WS" ]; then
      ws_marker="*"
    fi
    items="${items}tab:${chrome_wid}:${tab_idx}:${aero_wid} | [${ws}${ws_marker}] Chrome Tab - ${tab_title}
"
  else
    items="${items}tab:${chrome_wid}:${tab_idx}: | Chrome Tab - ${tab_title}
"
  fi
done <<< "$chrome_tabs"

# 3. Workspaces
while IFS= read -r line; do
  [ -z "$line" ] && continue
  ws=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')
  win_count=$(aerospace list-windows --workspace "$ws" --count 2>/dev/null)
  
  if [ "$win_count" -gt 0 ]; then
    apps=$(aerospace list-windows --workspace "$ws" --format "%{app-name}" 2>/dev/null | sort -u | tr '\n' ', ' | sed 's/,$//')
    items="${items}ws:${ws} | Workspace ${ws} (${win_count} windows: ${apps})
"
  else
    items="${items}ws:${ws} | Workspace ${ws} (empty)
"
  fi
done <<< "$(aerospace list-workspaces --all 2>/dev/null)"

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
    
    # First: focus the AeroSpace window (switches to correct workspace/monitor)
    if [ -n "$aero_wid" ]; then
      aerospace focus --window-id "$aero_wid" 2>/dev/null
    fi
    
    # Then: switch only the tab in that specific Chrome window (no reordering)
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

# Refresh bar
~/.config/aerospace/scripts/refresh-bar.sh
