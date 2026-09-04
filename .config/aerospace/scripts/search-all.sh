#!/opt/homebrew/bin/bash
# search-all.sh — fast unified search: windows, Chrome tabs (title+URL), workspaces
#
# Correctness design (fixes "wrong tab / wrong thing"):
#   - The picker shows CLEAN labels only (no routing ids in the visible text, so
#     fuzzy matching can never latch onto a hidden id and pick the wrong row).
#   - `choose -i` returns the INDEX of the selection; we route via a parallel
#     ROUTES[] array. No parsing of visible text = zero ambiguity.
#   - Tabs are activated by URL (stable), not by cached index (which goes stale
#     when tabs are opened/closed/reordered).
#
# Speed design:
#   - AeroSpace windows + workspaces (~60ms) shown immediately; never block on
#     Chrome's ~0.7s AppleScript.
#   - Chrome tabs read from a 3s cache, refreshed detached in the background.
#   - Zero subshell forks in the build loops (bash parameter expansion only).

set -o pipefail

TMPDIR_SEARCH="/tmp/aerospace-search"
mkdir -p "$TMPDIR_SEARCH"
CHROME_CACHE="$TMPDIR_SEARCH/chrome.cache"
CHROME_TTL=3   # seconds

# ---- Relevance ranking (frecency) ----
USAGE_DIR="$HOME/.config/aerospace/usage"
SEARCH_HISTORY="$USAGE_DIR/search_history.tsv"
mkdir -p "$USAGE_DIR"

# Stable ranking key per item: win:<app>, tab:<url>, ws:<name>.
declare -A FRECENCY
if [ -f "$SEARCH_HISTORY" ]; then
  while IFS=$'\t' read -r rk score; do
    [ -n "$rk" ] && FRECENCY[$rk]="$score"
  done < <(awk -F'\t' -v now="$(date +%s)" '
    NF>=2 {
      ts=$1; key=$2
      for (i=3;i<=NF;i++) key=key FS $i
      age=(now-ts)/86400.0
      if (age<0) age=0
      w=exp(-0.693147*age/14.0)        # 14-day half-life
      s[key]+=w
    }
    END { for (k in s) printf "%s\t%.6f\n", k, s[k] }
  ' "$SEARCH_HISTORY" 2>/dev/null)
fi

# ROWS[i] = "score US type US routeA US routeB US label" (US = \x1f unit sep).
# Using \x1f (not TAB) as the field sep so `read` preserves EMPTY fields — TAB is
# an IFS whitespace char and collapses empties, which corrupted routing.
US=$'\x1f'
ROWS=()
add_item() {
  local rankkey="$1" itype="$2" rA="$3" rB="$4" label="$5"
  local sc="${FRECENCY[$rankkey]:-0}"
  ROWS+=("${sc}${US}${itype}${US}${rA}${US}${rB}${US}${label}")
}

# Leaner Chrome enumeration. Fields separated by ASCII unit separator (\x1f).
CHROME_DELIM=$'\x1f'
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

refresh_chrome_cache() {
  ( osascript -e "$CHROME_QUERY" 2>/dev/null > "$CHROME_CACHE.tmp.$$" \
      && mv -f "$CHROME_CACHE.tmp.$$" "$CHROME_CACHE" \
      || rm -f "$CHROME_CACHE.tmp.$$" ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

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

if ! cache_fresh; then
  refresh_chrome_cache
fi

# 1. AeroSpace windows.  route: type=win, A=window-id
while IFS='|' read -r wid ws app title; do
  [ -z "$wid" ] && continue
  wid="${wid// /}"
  ws="${ws// /}"
  app="${app#"${app%%[![:space:]]*}"}"; app="${app%"${app##*[![:space:]]}"}"
  title="${title#"${title%%[![:space:]]*}"}"; title="${title%"${title##*[![:space:]]}"}"
  marker=""
  [ "$ws" = "$FOCUSED_WS" ] && marker="*"
  add_item "win:${app}" "win" "$wid" "" "[${ws}${marker}] ${app} — ${title}"
done <<< "$ALL_WINDOWS"

# 2. Workspaces.  route: type=ws, A=workspace-name
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

ALL_WS="${SPACESUIT_WORKSPACES:-1 2 3 4 5 6 7 8 9 10 A B C D E F}"
for ws in $ALL_WS; do
  count=${WS_COUNTS[$ws]:-0}
  if [ "$count" -gt 0 ]; then
    add_item "ws:${ws}" "ws" "$ws" "" "Workspace ${ws} · ${WS_APPS[$ws]}"
  else
    add_item "ws:${ws}" "ws" "$ws" "" "Workspace ${ws} · (empty)"
  fi
done

# 3. Chrome tabs from cache.  route: type=tab, A=chrome-window-id, B=url
if [ -f "$CHROME_CACHE" ]; then
  while IFS="$CHROME_DELIM" read -r cwid tidx aidx ttitle turl; do
    [ -z "$cwid" ] && continue
    cwid="${cwid// /}"
    ttitle="${ttitle#"${ttitle%%[![:space:]]*}"}"; ttitle="${ttitle%"${ttitle##*[![:space:]]}"}"
    turl="${turl#"${turl%%[![:space:]]*}"}"; turl="${turl%"${turl##*[![:space:]]}"}"
    # Compact host for display; full URL stays in the route (B) + searchable tail.
    host="${turl#*://}"; host="${host%%/*}"
    add_item "tab:${turl}" "tab" "$cwid" "$turl" "Tab · ${ttitle} — ${host}"
  done < "$CHROME_CACHE"
fi

# ---- Rank: stable sort rows by score desc, keep original index as tiebreak ----
# Build "idx<TAB>score<TAB>rowdata"; sort by score desc, then idx asc (stable).
order=$(
  for i in "${!ROWS[@]}"; do
    printf '%s\t%s\n' "$i" "${ROWS[$i]%%${US}*}"
  done | sort -t$'\t' -k2,2 -rns -k1,1n | awk -F'\t' '{print $1}'
)

# Build the display list + a routing table indexed by DISPLAY position.
DISPLAY=""
declare -a R_TYPE R_A R_B R_LABEL R_RANK
di=0
while IFS= read -r src; do
  [ -z "$src" ] && continue
  IFS="$US" read -r sc itype rA rB label <<< "${ROWS[$src]}"
  # A scored item has a non-"0" frecency (formatted %.6f); default is "0".
  star=""
  case "$sc" in 0|0.000000|"") ;; *) star="★ " ;; esac
  R_TYPE[$di]="$itype"; R_A[$di]="$rA"; R_B[$di]="$rB"; R_LABEL[$di]="$label"
  case "$itype" in
    win) R_RANK[$di]="win:";;   # filled at pick time from label if needed
    ws)  R_RANK[$di]="ws:${rA}";;
    tab) R_RANK[$di]="tab:${rB}";;
  esac
  DISPLAY+="${star}${label}"$'\n'
  di=$((di+1))
done <<< "$order"

[ "$di" -eq 0 ] && exit 0

# ---- Show picker; get the INDEX of the chosen row ----
sel_idx=$(printf '%s' "$DISPLAY" | choose -i)
# choose returns empty (esc) or a numeric index.
case "$sel_idx" in
  ''|*[!0-9]*) exit 0 ;;
esac
[ "$sel_idx" -ge "$di" ] && exit 0

itype="${R_TYPE[$sel_idx]}"
rA="${R_A[$sel_idx]}"
rB="${R_B[$sel_idx]}"
label="${R_LABEL[$sel_idx]}"

# ---- Log the pick for frecency ----
log_pick() {
  local rk="$1"
  [ -z "$rk" ] && return
  printf '%s\t%s\n' "$(date +%s)" "$rk" >> "$SEARCH_HISTORY"
  tail -5000 "$SEARCH_HISTORY" > "$SEARCH_HISTORY.tmp" 2>/dev/null \
    && mv -f "$SEARCH_HISTORY.tmp" "$SEARCH_HISTORY" 2>/dev/null
}

# ---- Act on the selected row (routed by index, never by visible text) ----
case "$itype" in
  win)
    # rank key = app name, parsed from label "[ws] App — title"
    _lbl="${label#*] }"; app_name="${_lbl%% — *}"
    log_pick "win:${app_name}"
    aerospace focus --window-id "$rA" 2>/dev/null
    ;;
  ws)
    log_pick "ws:${rA}"
    aerospace workspace "$rA" 2>/dev/null
    ;;
  tab)
    chrome_wid="$rA"
    tab_url="$rB"
    log_pick "tab:${tab_url}"
    esc_url="${tab_url//\\/\\\\}"; esc_url="${esc_url//\"/\\\"}"
    # Activate the tab whose URL matches — prefer the cached window, then any.
    # CRITICAL: reference windows by ID (window id X), never by positional index,
    # because `set index ... to 1` reorders windows and would invalidate a saved
    # position (this caused the wrong tab to be activated).
    resolved_title=$(osascript -e "tell application \"Google Chrome\"
      set targetURL to \"$esc_url\"
      set foundId to missing value
      set foundTab to 0
      -- Pass 1: the cached window (by id), matched by URL.
      repeat with w in windows
        if (id of w as text) is \"$chrome_wid\" then
          set tabs_u to URL of tabs of w
          repeat with ti from 1 to (count of tabs_u)
            if (item ti of tabs_u) is targetURL then
              set foundId to (id of w as text)
              set foundTab to ti
              exit repeat
            end if
          end repeat
        end if
        if foundId is not missing value then exit repeat
      end repeat
      -- Pass 2: any window, matched by URL.
      if foundId is missing value then
        repeat with w in windows
          set tabs_u to URL of tabs of w
          repeat with ti from 1 to (count of tabs_u)
            if (item ti of tabs_u) is targetURL then
              set foundId to (id of w as text)
              set foundTab to ti
              exit repeat
            end if
          end repeat
          if foundId is not missing value then exit repeat
        end repeat
      end if
      if foundId is missing value then return \"\"
      -- Operate strictly via `window id` so reordering can't misdirect us.
      set active tab index of (window id (foundId as integer)) to foundTab
      set index of (window id (foundId as integer)) to 1
      activate
      return (title of active tab of (window id (foundId as integer)))
    end tell" 2>/dev/null)
    # Focus the correct AeroSpace Chrome window by its (now-updated) title.
    aero_wid=""
    if [ -n "$resolved_title" ]; then
      FRESH_WINDOWS=$(aerospace list-windows --all --format "%{window-id}|%{app-name}|%{window-title}" 2>/dev/null)
      while IFS='|' read -r awid aapp atitle; do
        [ "$aapp" = "Google Chrome" ] || continue
        if [[ "$atitle" == *"$resolved_title"* ]]; then
          aero_wid="${awid// /}"; break
        fi
      done <<< "$FRESH_WINDOWS"
    fi
    if [ -z "$aero_wid" ]; then
      aero_wid=$(printf '%s\n' "$ALL_WINDOWS" | grep -i '|Google Chrome|' | head -1 | cut -d'|' -f1)
      aero_wid="${aero_wid// /}"
    fi
    [ -n "$aero_wid" ] && aerospace focus --window-id "$aero_wid" 2>/dev/null
    ;;
esac

~/.config/aerospace/scripts/refresh-bar.sh
