#!/opt/homebrew/bin/bash
# Update SketchyBar top 5 apps + write keybind map for alt-o 1-5

USAGE_DIR="$HOME/.config/aerospace/usage"
FREQ_FILE="$USAGE_DIR/frequencies.tsv"
BIND_FILE="$USAGE_DIR/top5.sh"

# Real app icons for the alt-o pills (same pipeline as workspace pills).
ICON_HELPERS="$HOME/.config/sketchybar/plugins/icon-helpers.sh"
# shellcheck source=/dev/null
[ -f "$ICON_HELPERS" ] && source "$ICON_HELPERS"

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
    Terminal)        TOP_CMDS[$i]="open -a Terminal"; TOP_ICONS[$i]="" ;;
    Ghostty)         TOP_CMDS[$i]="open -a Ghostty"; TOP_ICONS[$i]="" ;;
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
      "Microsoft Excel") short="Excel" ;;
      "Microsoft Word") short="Word" ;;
      "Microsoft PowerPoint") short="PPT" ;;
      "Visual Studio Code") short="VSCode" ;;
      "Joule Desktop") short="Joule" ;;
    esac

    # Bake [index][icon][name] into ONE strip so spacing is uniform (no image
    # vs. label reservation conflict). Pin item width to the displayed size
    # (strip_px/2 + pad) so SketchyBar reserves exactly what it draws.
    strip=""; strip_px=0
    if type build_top_strip >/dev/null 2>&1; then
      out="$(build_top_strip "$idx" "${TOP_APPS[$j]}")"
      strip="${out%%|*}"; strip_px="${out##*|}"
      [[ "$strip_px" =~ ^[0-9]+$ ]] || strip_px=0
    fi

    if [ -n "$strip" ] && [ -f "$strip" ] && [ "$strip_px" -gt 0 ]; then
      pill_w=$(( strip_px / 2 + 12 ))
      sketchybar --set top_app.$idx \
        icon.drawing=off icon="" \
        label.drawing=off label="" \
        padding_left="${SPACESUIT_PILL_GAP:-6}" \
        padding_right="${SPACESUIT_PILL_GAP:-6}" \
        background.image="$strip" \
        background.image.drawing=on \
        background.image.scale=0.5 \
        width=$pill_w \
        drawing=on 2>/dev/null
    else
      # Fallback: no icon resolved — index + name text only.
      sketchybar --set top_app.$idx \
        background.image.drawing=off \
        icon.drawing=on icon="$idx:" icon.color=0xffcba6f7 \
        label="$short" \
        label.drawing=on \
        label.color=0xffa6adc8 \
        width=0 \
        drawing=on 2>/dev/null
    fi
  else
    sketchybar --set top_app.$idx drawing=off 2>/dev/null
  fi
done
