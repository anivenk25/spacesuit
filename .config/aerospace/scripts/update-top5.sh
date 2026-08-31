#!/opt/homebrew/bin/bash
# Update SketchyBar top 5 apps + write keybind map for alt-o 1-5

USAGE_DIR="$HOME/.config/aerospace/usage"
FREQ_FILE="$USAGE_DIR/frequencies.tsv"
BIND_FILE="$USAGE_DIR/top5.sh"

[ ! -f "$FREQ_FILE" ] && exit 0

# Read top 5 apps
declare -a TOP_APPS TOP_CMDS TOP_ICONS
i=0
while IFS=$'\t' read -r count app; do
  [ -z "$app" ] && continue
  [ $i -ge 5 ] && break

  TOP_APPS[$i]="$app"

  # Map app name to launch command
  case "$app" in
    "Google Chrome") TOP_CMDS[$i]="open -a 'Google Chrome'"; TOP_ICONS[$i]="" ;;
    kitty)           TOP_CMDS[$i]="open -n -a /Applications/kitty.app"; TOP_ICONS[$i]="" ;;
    "Microsoft Outlook") TOP_CMDS[$i]="open -a 'Microsoft Outlook'"; TOP_ICONS[$i]="" ;;
    "Microsoft Teams")   TOP_CMDS[$i]="open -a 'Microsoft Teams'"; TOP_ICONS[$i]="" ;;
    "Visual Studio Code") TOP_CMDS[$i]="open -a 'Visual Studio Code'"; TOP_ICONS[$i]="" ;;
    "Joule Desktop") TOP_CMDS[$i]="open -a 'Joule Desktop'"; TOP_ICONS[$i]="" ;;
    Finder)          TOP_CMDS[$i]="open -a Finder"; TOP_ICONS[$i]="" ;;
    Safari)          TOP_CMDS[$i]="open -a Safari"; TOP_ICONS[$i]="" ;;
    Slack)           TOP_CMDS[$i]="open -a Slack"; TOP_ICONS[$i]="" ;;
    *)               TOP_CMDS[$i]="open -a '$app'"; TOP_ICONS[$i]="" ;;
  esac

  i=$((i + 1))
done < "$FREQ_FILE"

# Write keybind map (sourced by launcher script)
cat > "$BIND_FILE" << 'HEADER'
#!/opt/homebrew/bin/bash
# Auto-generated — top 5 app launch commands
HEADER

for j in $(seq 0 4); do
  if [ -n "${TOP_CMDS[$j]}" ]; then
    echo "TOP_CMD_$((j+1))='${TOP_CMDS[$j]}'" >> "$BIND_FILE"
    echo "TOP_APP_$((j+1))='${TOP_APPS[$j]}'" >> "$BIND_FILE"
  fi
done
chmod +x "$BIND_FILE"

# Update SketchyBar items
for j in $(seq 0 4); do
  idx=$((j + 1))
  if [ -n "${TOP_APPS[$j]}" ]; then
    # Shorten app name
    short="${TOP_APPS[$j]}"
    case "$short" in
      "Google Chrome") short="Chrome" ;;
      "Microsoft Outlook") short="Mail" ;;
      "Microsoft Teams") short="Teams" ;;
      "Visual Studio Code") short="VSCode" ;;
      "Joule Desktop") short="Joule" ;;
    esac

    sketchybar --set top_app.$idx \
      icon="${TOP_ICONS[$j]}" \
      icon.color=0xffcba6f7 \
      label="$idx:$short" \
      label.drawing=on \
      label.color=0xffa6adc8 \
      drawing=on 2>/dev/null
  else
    sketchybar --set top_app.$idx drawing=off 2>/dev/null
  fi
done
