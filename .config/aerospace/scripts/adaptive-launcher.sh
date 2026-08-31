#!/opt/homebrew/bin/bash
# Adaptive launcher — shows most-used apps, sites, workspaces
# Ranked by usage frequency + time-of-day patterns

USAGE_DIR="$HOME/.config/aerospace/usage"
FREQ_FILE="$USAGE_DIR/frequencies.tsv"
HOUR=$(date +%H)
HOUR_FILE="$USAGE_DIR/hour_${HOUR}.tsv"

items=""

# ---- Section 1: Frequently used apps (ranked) ----
if [ -f "$FREQ_FILE" ]; then
  items="${items}--- Most Used Apps ---
"
  # Get top apps and build launch commands
  while IFS=$'\t' read -r count app; do
    [ -z "$app" ] && continue
    case "$app" in
      "Google Chrome") cmd="open -a 'Google Chrome'" ;;
      kitty) cmd="open -n -a /Applications/kitty.app" ;;
      "Microsoft Outlook") cmd="open -a 'Microsoft Outlook'" ;;
      "Microsoft Teams") cmd="open -a 'Microsoft Teams'" ;;
      "Visual Studio Code") cmd="open -a 'Visual Studio Code'" ;;
      "Joule Desktop") cmd="open -a 'Joule Desktop'" ;;
      Finder) cmd="open -a Finder" ;;
      *) cmd="open -a '$app'" ;;
    esac
    items="${items}app:${cmd} | ${app} (used ${count}x)
"
  done < <(head -8 "$FREQ_FILE")
fi

# ---- Section 2: Time-of-day suggestions ----
if [ -f "$HOUR_FILE" ]; then
  items="${items}--- Usually Open Now (${HOUR}:00) ---
"
  # Top apps for this hour
  awk -F'\t' '{print $1}' "$HOUR_FILE" | sort | uniq -c | sort -rn | head -5 | while read -r count app; do
    [ -z "$app" ] && continue
    case "$app" in
      "Google Chrome") cmd="open -a 'Google Chrome'" ;;
      kitty) cmd="open -n -a /Applications/kitty.app" ;;
      "Microsoft Outlook") cmd="open -a 'Microsoft Outlook'" ;;
      "Microsoft Teams") cmd="open -a 'Microsoft Teams'" ;;
      *) cmd="open -a '$app'" ;;
    esac
    items="${items}app:${cmd} | ${app} (${count}x at this hour)
"
  done
fi

# ---- Section 3: Quick sites ----
items="${items}--- Quick Sites ---
url:https://github.com | GitHub
url:https://mail.google.com | Gmail
url:https://outlook.office.com | Outlook Web
url:https://teams.microsoft.com | Teams Web
url:https://chat.openai.com | ChatGPT
"

# ---- Section 4: Quick actions ----
items="${items}--- Actions ---
action:new-terminal | New Terminal (Kitty)
action:new-chrome | New Chrome Window
action:new-note | New TextEdit Note
action:lock-screen | Lock Screen
"

# ---- Section 5: Workspaces with content ----
items="${items}--- Workspaces ---
"
ALL_WINDOWS=$(aerospace list-windows --all --format "%{window-id}|%{workspace}|%{app-name}|%{window-title}" 2>/dev/null)
declare -A WS_APPS
while IFS='|' read -r wid ws app title; do
  [ -z "$ws" ] && continue
  ws=$(echo "$ws" | tr -d ' ')
  app=$(echo "$app" | sed 's/^ *//;s/ *$//')
  if [ -n "$app" ] && [[ "${WS_APPS[$ws]}" != *"$app"* ]]; then
    WS_APPS[$ws]="${WS_APPS[$ws]:+${WS_APPS[$ws]}, }$app"
  fi
done <<< "$ALL_WINDOWS"

for ws in $(aerospace list-workspaces --all 2>/dev/null); do
  if [ -n "${WS_APPS[$ws]}" ]; then
    items="${items}ws:${ws} | Workspace ${ws} (${WS_APPS[$ws]})
"
  fi
done

# ---- Show picker ----
selected=$(echo "$items" | grep -v '^$' | grep -v '^---' | choose)
[ -z "$selected" ] && exit 0

prefix=$(echo "$selected" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')
type=$(echo "$prefix" | cut -d: -f1)

case "$type" in
  app)
    cmd=$(echo "$prefix" | cut -d: -f2-)
    eval "$cmd" 2>/dev/null
    ;;
  url)
    url=$(echo "$prefix" | cut -d: -f2-)
    open "$url" 2>/dev/null
    ;;
  action)
    action=$(echo "$prefix" | cut -d: -f2-)
    case "$action" in
      new-terminal) open -n -a /Applications/kitty.app ;;
      new-chrome) open -na "Google Chrome" --args --new-window ;;
      new-note) open -n -a TextEdit ;;
      lock-screen) pmset displaysleepnow ;;
    esac
    ;;
  ws)
    ws_name=$(echo "$prefix" | cut -d: -f2)
    aerospace workspace "$ws_name" 2>/dev/null
    ;;
esac

~/.config/aerospace/scripts/refresh-bar.sh
