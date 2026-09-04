#!/opt/homebrew/bin/bash
# search-all.sh — fast unified search: windows, Chrome tabs (title+URL), workspaces
#
# Speed design:
#   - AeroSpace windows + workspaces are gathered in ~60ms and shown IMMEDIATELY.
#   - Chrome tabs are read from a short-lived cache (instant) and refreshed in the
#     background, so the picker never blocks on Chrome's ~0.7s AppleScript.
#   - Leaner single-pass AppleScript: batch-fetches `title of tabs`/`URL of tabs`
#     and emits windowId + tabIndex directly (no O(win*tab) title-matching loop).
#   - Zero subshell forks in the build loops (bash parameter expansion only).
#   - URL is part of each tab's searchable text (type a domain to match a tab).

set -o pipefail

TMPDIR_SEARCH="/tmp/aerospace-search"
mkdir -p "$TMPDIR_SEARCH"
CHROME_CACHE="$TMPDIR_SEARCH/chrome.cache"
CHROME_TTL=3   # seconds

# Leaner Chrome enumeration. Fields separated by the unambiguous token DELIM.
# Output lines: winId DELIM tabIdx DELIM activeIdx DELIM title DELIM url
CHROME_DELIM=$'\x1f'   # ASCII unit separator — never appears in titles/URLs
CHROME_QUERY='
set d to (ASCII character 31)
set out to ""
tell application "Google Chrome"
  repeat with wi from 1 to (count of windows)
    set w to window wi
    set wid to id of w
    set ai to active tab index of w
    set tt to title of tabs of w
    set uu to URL of tabs of w
    repeat with i from 1 to (count of tt)
      set out to out & wid & d & i & d & ai & d & (item i of tt) & d & (item i of uu) & linefeed
    end repeat
  end repeat
end tell
return out'

# Refresh the Chrome cache in the background (atomic write via temp + mv).
refresh_chrome_cache() {
  # Fully detached (own session, no controlling shell) so we NEVER wait on it.
  ( osascript -e "$CHROME_QUERY" 2>/dev/null > "$CHROME_CACHE.tmp.$$" \
      && mv -f "$CHROME_CACHE.tmp.$$" "$CHROME_CACHE" \
      || rm -f "$CHROME_CACHE.tmp.$$" ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# Is the cache fresh (exists and younger than TTL)?
cache_fresh() {
  [ -f "$CHROME_CACHE" ] || return 1
  local age
  age=$(( $(date +%s) - $(stat -f %m "$CHROME_CACHE" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$CHROME_TTL" ]
}

# ---- Instant data: AeroSpace windows + workspaces (~60ms) ----
ALL_WINDOWS=$(aerospace list-windows --all --format "%{window-id}|%{workspace}|%{app-name}|%{window-title}" 2>/dev/null)
FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null | head -1)
FOCUSED_WS="${FOCUSED_WS// /}"

# Kick off Chrome refresh now if stale; use existing cache meanwhile.
if ! cache_fresh; then
  refresh_chrome_cache
fi

items=""

# 1. AeroSpace windows (no forks — pure parameter expansion)
while IFS='|' read -r wid ws app title; do
  [ -z "$wid" ] && continue
  wid="${wid// /}"
  ws="${ws// /}"
  # trim leading/trailing spaces from app/title
  app="${app#"${app%%[![:space:]]*}"}"; app="${app%"${app##*[![:space:]]}"}"
  title="${title#"${title%%[![:space:]]*}"}"; title="${title%"${title##*[![:space:]]}"}"
  marker=""
  [ "$ws" = "$FOCUSED_WS" ] && marker="*"
  items="${items}win:${wid} | [${ws}${marker}] ${app} - ${title}
"
done <<< "$ALL_WINDOWS"

# 2. Workspaces — derive counts/apps from the window data already fetched (no forks)
declare -A WS_COUNTS WS_APPS
while IFS='|' read -r wid ws app title; do
  [ -z "$ws" ] && continue
  ws="${ws// /}"
  app="${app#"${app%%[![:space:]]*}"}"; app="${app%"${app##*[![:space:]]}"}"
  WS_COUNTS[$ws]=$(( ${WS_COUNTS[$ws]:-0} + 1 ))
  if [ -n "$app" ] && [[ " ${WS_APPS[$ws]} " != *" $app "* ]]; then
    WS_APPS[$ws]="${WS_APPS[$ws]:+${WS_APPS[$ws]}, }$app"
  fi
done <<< "$ALL_WINDOWS"

# Persistent workspace set (from ~/.aerospace.toml). Avoids a ~0.45s
# `list-workspaces --all` call on the hot path; override via SPACESUIT_WORKSPACES.
ALL_WS="${SPACESUIT_WORKSPACES:-1 2 3 4 5 6 7 8 9 10 A B C D E F}"
for ws in $ALL_WS; do
  count=${WS_COUNTS[$ws]:-0}
  if [ "$count" -gt 0 ]; then
    items="${items}ws:${ws} | Workspace ${ws} (${count} windows: ${WS_APPS[$ws]})
"
  else
    items="${items}ws:${ws} | Workspace ${ws} (empty)
"
  fi
done

# 3. Chrome tabs from cache (instant). Each line carries winId+tabIdx directly, so
#    activation needs no re-scan. URL is appended (searchable + visible, secondary).
if [ -f "$CHROME_CACHE" ]; then
  while IFS="$CHROME_DELIM" read -r cwid tidx aidx ttitle turl; do
    [ -z "$cwid" ] && continue
    cwid="${cwid// /}"
    tidx="${tidx// /}"
    ttitle="${ttitle#"${ttitle%%[![:space:]]*}"}"; ttitle="${ttitle%"${ttitle##*[![:space:]]}"}"
    turl="${turl#"${turl%%[![:space:]]*}"}"; turl="${turl%"${turl##*[![:space:]]}"}"
    items="${items}tab:${cwid}:${tidx} | Chrome - ${ttitle}  —  ${turl}
"
  done < "$CHROME_CACHE"
fi

# ---- Show picker ----
selected=$(printf '%s' "$items" | grep -v '^$' | choose)
[ -z "$selected" ] && exit 0

# ---- Act on selection ----
# prefix = text before first '|', trimmed.
prefix="${selected%%|*}"
prefix="${prefix#"${prefix%%[![:space:]]*}"}"; prefix="${prefix%"${prefix##*[![:space:]]}"}"
type="${prefix%%:*}"

case "$type" in
  win)
    wid="${prefix#win:}"
    aerospace focus --window-id "$wid" 2>/dev/null
    ;;
  tab)
    rest="${prefix#tab:}"
    chrome_wid="${rest%%:*}"
    tab_idx="${rest##*:}"
    # Focus the Chrome window in AeroSpace if we can find it (match by app), then
    # activate the exact tab. Window focus is best-effort; tab activation is exact.
    aero_wid=$(printf '%s\n' "$ALL_WINDOWS" | grep -i '|Google Chrome|' | head -1 | cut -d'|' -f1)
    aero_wid="${aero_wid// /}"
    [ -n "$aero_wid" ] && aerospace focus --window-id "$aero_wid" 2>/dev/null
    # Activate the exact tab AND raise its window to the front.
    osascript -e "tell application \"Google Chrome\"
      set idx to 0
      repeat with wi from 1 to (count of windows)
        if (id of window wi as text) is \"$chrome_wid\" then set idx to wi
      end repeat
      if idx > 0 then
        set active tab index of window idx to $tab_idx
        set index of window idx to 1
      end if
      activate
    end tell" 2>/dev/null
    ;;
  ws)
    ws_name="${prefix#ws:}"
    aerospace workspace "$ws_name" 2>/dev/null
    ;;
esac

~/.config/aerospace/scripts/refresh-bar.sh
