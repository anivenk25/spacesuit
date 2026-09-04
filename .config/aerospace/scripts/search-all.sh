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

# ---- Relevance ranking (frecency) ----
# Every pick is logged to search_history.tsv; results are ordered so items you
# choose often/recently float to the top. `choose` keeps input order for equal
# fuzzy matches, so your favourites lead when the query is empty/weak, while
# fuzzy typing still narrows normally.
USAGE_DIR="$HOME/.config/aerospace/usage"
SEARCH_HISTORY="$USAGE_DIR/search_history.tsv"
mkdir -p "$USAGE_DIR"

# A stable ranking key per item (window ids/tab ids churn between runs, so rank
# windows by app name and tabs by URL — both stable identifiers).
#   win -> "win:<app>"      tab -> "tab:<url>"      ws -> "ws:<name>"
declare -A FRECENCY
if [ -f "$SEARCH_HISTORY" ]; then
  # Frecency = sum over picks of 0.5^(age_days / HALFLIFE). Recent+frequent wins.
  # One awk pass over the (bounded) history file — a few ms.
  while IFS=$'\t' read -r rk score; do
    [ -n "$rk" ] && FRECENCY[$rk]="$score"
  done < <(awk -F'\t' -v now="$(date +%s)" '
    NF>=2 {
      ts=$1; key=$2
      for (i=3;i<=NF;i++) key=key FS $i        # keep any tabs in the key intact
      age=(now-ts)/86400.0                      # age in days
      if (age<0) age=0
      w=exp(-0.693147*age/14.0)                 # 14-day half-life
      s[key]+=w
    }
    END { for (k in s) printf "%s\t%.6f\n", k, s[k] }
  ' "$SEARCH_HISTORY" 2>/dev/null)
fi

# Append a scored item line "<score>\t<prefix> | <label>\n" to the global
# $scored buffer WITHOUT forking a subshell (printf -v). Score drives the sort
# and is stripped before the picker sees it; top-scored items get a ★ marker.
scored=""
emit() {
  local rankkey="$1" prefix="$2" label="$3"
  local sc="${FRECENCY[$rankkey]:-0}" _line
  printf -v _line '%s\t%s | %s\n' "$sc" "$prefix" "$label"
  scored+="$_line"
}

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

# $scored collects "score\tprefix | label" lines (populated by emit); sorted
# before display. Initialized above where emit() is defined.

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
  emit "win:${app}" "win:${wid}" "[${ws}${marker}] ${app} - ${title}"
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
    emit "ws:${ws}" "ws:${ws}" "Workspace ${ws} (${count} windows: ${WS_APPS[$ws]})"
  else
    emit "ws:${ws}" "ws:${ws}" "Workspace ${ws} (empty)"
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
    emit "tab:${turl}" "tab:${cwid}:${tidx}" "Chrome - ${ttitle}  —  ${turl}"
  done < "$CHROME_CACHE"
fi

# ---- Rank + show picker ----
# Sort by frecency score (desc), stable so equal-score items keep insertion
# order (windows, then workspaces, then tabs). Mark items with any history (★),
# then strip the leading "score\t" column before the picker sees it.
items=$(printf '%s' "$scored" | grep -v '^[[:space:]]*$' \
  | sort -t$'\t' -k1,1 -rns \
  | awk -F'\t' '{
      score=$1; sub(/^[^\t]*\t/, "")   # strip leading score column
      if (score+0 > 0) sub(/ \| /, " | ★ ")
      print
    }')

selected=$(printf '%s\n' "$items" | grep -v '^$' | choose)
[ -z "$selected" ] && exit 0

# ---- Act on selection ----
# prefix = text before first '|', trimmed.
prefix="${selected%%|*}"
prefix="${prefix#"${prefix%%[![:space:]]*}"}"; prefix="${prefix%"${prefix##*[![:space:]]}"}"
type="${prefix%%:*}"

# Record the pick for frecency ranking. rank_key mirrors emit():
#   win -> win:<app>   tab -> tab:<url>   ws -> ws:<name>
# Derived from the selected LABEL (stable across runs), not the volatile ids.
log_pick() {
  local rk="$1"
  [ -z "$rk" ] && return
  printf '%s\t%s\n' "$(date +%s)" "$rk" >> "$SEARCH_HISTORY"
  # Keep history bounded (last 5000 picks).
  tail -5000 "$SEARCH_HISTORY" > "$SEARCH_HISTORY.tmp" 2>/dev/null \
    && mv -f "$SEARCH_HISTORY.tmp" "$SEARCH_HISTORY" 2>/dev/null
}

# label = text after first "| ", with any leading "★ " marker stripped.
label="${selected#*| }"
label="${label#★ }"

case "$type" in
  win)
    wid="${prefix#win:}"
    # rank key = app name = label between the "] " and " - ".
    _lbl="${label#*] }"; app_name="${_lbl%% - *}"
    log_pick "win:${app_name}"
    aerospace focus --window-id "$wid" 2>/dev/null
    ;;
  tab)
    rest="${prefix#tab:}"
    chrome_wid="${rest%%:*}"
    tab_idx="${rest##*:}"
    # rank key = URL = text after the last "  —  " separator.
    tab_url="${label##*  —  }"
    log_pick "tab:${tab_url}"
    # Activate by URL (stable), NOT the cached index (which goes stale when tabs
    # are opened/closed/reordered). Strategy:
    #   1) Prefer the originally-cached window id; find the tab whose URL matches.
    #   2) If not found there, search ALL Chrome windows for the URL.
    #   3) Fall back to the cached index in the cached window only if URL fails.
    # Returns the resolved Chrome window id so we focus the CORRECT AeroSpace win.
    esc_url="${tab_url//\\/\\\\}"; esc_url="${esc_url//\"/\\\"}"
    resolved_title=$(osascript -e "tell application \"Google Chrome\"
      set targetURL to \"$esc_url\"
      set foundWin to missing value
      set foundTab to 0
      -- Pass 1: the cached window, matched by URL
      repeat with wi from 1 to (count of windows)
        if (id of window wi as text) is \"$chrome_wid\" then
          set tabs_u to URL of tabs of window wi
          repeat with ti from 1 to (count of tabs_u)
            if (item ti of tabs_u) is targetURL then
              set foundWin to wi
              set foundTab to ti
              exit repeat
            end if
          end repeat
        end if
      end repeat
      -- Pass 2: any window, matched by URL
      if foundWin is missing value then
        repeat with wi from 1 to (count of windows)
          set tabs_u to URL of tabs of window wi
          repeat with ti from 1 to (count of tabs_u)
            if (item ti of tabs_u) is targetURL then
              set foundWin to wi
              set foundTab to ti
              exit repeat
            end if
          end repeat
          if foundWin is not missing value then exit repeat
        end repeat
      end if
      -- Pass 3: fall back to cached index in the cached window
      if foundWin is missing value then
        repeat with wi from 1 to (count of windows)
          if (id of window wi as text) is \"$chrome_wid\" then
            set foundWin to wi
            set foundTab to $tab_idx
          end if
        end repeat
      end if
      if foundWin is not missing value then
        set active tab index of window foundWin to foundTab
        set index of window foundWin to 1
        activate
        return (title of active tab of window foundWin)
      end if
      return \"\"
    end tell" 2>/dev/null)
    # Focus the CORRECT AeroSpace Chrome window. AeroSpace's window-id differs from
    # Chrome's, but the AeroSpace window title tracks the active tab's title. We
    # just made the target tab active, so RE-QUERY AeroSpace (fresh titles) and
    # match the Chrome window whose title contains the resolved tab title.
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
  ws)
    ws_name="${prefix#ws:}"
    log_pick "ws:${ws_name}"
    aerospace workspace "$ws_name" 2>/dev/null
    ;;
esac

~/.config/aerospace/scripts/refresh-bar.sh
