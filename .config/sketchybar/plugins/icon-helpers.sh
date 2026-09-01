#!/opt/homebrew/bin/bash
# Spacesuit icon helpers — resolve real macOS app icons and composite them into
# per-workspace strip PNGs. Sourced by update-all-workspaces.sh.
#
# Caches:
#   ~/.cache/spacesuit/icons/<sanitized-bundle-id>.png   (one per app, permanent)
#   ~/.cache/spacesuit/strips/<hash>.png                 (one per app-set, reused)
#
# All functions are defensive: any failure falls back to the generic icon or an
# empty strip, never a broken command.

SPACESUIT_CACHE="${SPACESUIT_CACHE:-$HOME/.cache/spacesuit}"
ICON_CACHE="$SPACESUIT_CACHE/icons"
STRIP_CACHE="$SPACESUIT_CACHE/strips"
ICON_PX="${SPACESUIT_ICON_PX:-36}"   # source render size (retina-friendly)
NUM_PT="${SPACESUIT_NUM_PT:-30}"     # baked workspace-number point size
NUM_GAP="${SPACESUIT_NUM_GAP:-8}"    # px gap between number and first icon
# Number colors: light for non-focused pills, dark for the focused (mauve) pill.
NUM_COLOR_LIGHT="${SPACESUIT_NUM_COLOR_LIGHT:-#cdd6f4}"  # Catppuccin text
NUM_COLOR_DARK="${SPACESUIT_NUM_COLOR_DARK:-#11111b}"    # Catppuccin crust

# Resolve a bold monospace font file for baking the workspace number.
_find_font() {
  local f
  for f in \
    "$HOME/Library/Fonts/HackNerdFont-Bold.ttf" \
    "$HOME/Library/Fonts/HackNerdFont-Regular.ttf" \
    "/System/Library/Fonts/SFNSMono.ttf" \
    "/System/Library/Fonts/Menlo.ttc" \
    "/System/Library/Fonts/Monaco.ttf"; do
    [ -f "$f" ] && { printf '%s' "$f"; return; }
  done
  printf ''  # magick will use its default
}
NUM_FONT="${SPACESUIT_NUM_FONT:-$(_find_font)}"

# Bundled fallback icon (repo asset). Resolve relative to this script; if the
# repo asset can't be found (unusual layout), synthesize one in the cache.
_ICON_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -z "$GENERIC_ICON" ]; then
  GENERIC_ICON="$_ICON_HELPERS_DIR/../../../assets/generic-app.png"
fi

mkdir -p "$ICON_CACHE" "$STRIP_CACHE" 2>/dev/null

if [ ! -f "$GENERIC_ICON" ]; then
  _fallback="$SPACESUIT_CACHE/generic-app.png"
  if [ ! -f "$_fallback" ]; then
    magick -size ${ICON_PX}x${ICON_PX} xc:none \
      -fill '#585b70' -draw "roundrectangle 3,3 $((ICON_PX-3)),$((ICON_PX-3)) 7,7" \
      "$_fallback" >/dev/null 2>&1
  fi
  GENERIC_ICON="$_fallback"
fi

# Fast PNG width reader — first checks for a sidecar .w file (written at build
# time, zero-cost), then falls back to reading the PNG IHDR header via xxd.
_strip_px_w() {
  local f="$1" _w
  # Fast path: sidecar file (bash read = no fork)
  if [ -f "${f}.w" ]; then read -r _w < "${f}.w"; printf '%s' "$_w"; return; fi
  [ -f "$f" ] || { printf '0'; return; }
  local hex
  hex=$(xxd -s 16 -l 4 -p "$f" 2>/dev/null) || { printf '0'; return; }
  printf '%d' "0x${hex}" 2>/dev/null || printf '0'
}

# Fast filename-safe hash. Pure bash — no forks. Uses the string directly,
# replacing unsafe chars. Keys are short enough to be valid filenames.
_fast_hash() {
  local s="$1"
  s="${s// /_}"
  s="${s//:/-}"
  s="${s//#/H}"
  printf '%s' "$s"
}

# Make a bundle-id safe for a filename
_safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

# _icns_to_png <app-path> <out-png>
# Extract the app's .icns, convert to a square PNG at ICON_PX. Returns 0 on
# success (out written), 1 on failure.
_icns_to_png() {
  local app="$1" out="$2"
  [ -d "$app" ] || return 1

  # Find the .icns: CFBundleIconFile, else CFBundleIconName, else first *.icns
  local iconfile icns
  iconfile=$(defaults read "$app/Contents/Info" CFBundleIconFile 2>/dev/null)
  [ -z "$iconfile" ] && iconfile=$(defaults read "$app/Contents/Info" CFBundleIconName 2>/dev/null)
  if [ -n "$iconfile" ]; then
    icns="$app/Contents/Resources/${iconfile%.icns}.icns"
  fi
  if [ -z "$icns" ] || [ ! -f "$icns" ]; then
    icns=$(ls "$app/Contents/Resources/"*.icns 2>/dev/null | head -1)
  fi
  [ -z "$icns" ] || [ ! -f "$icns" ] && return 1

  # Convert to PNG (atomic: write temp then move)
  local tmp="$out.tmp.$$"
  if sips -s format png -Z "$ICON_PX" "$icns" --out "$tmp" >/dev/null 2>&1 && [ -s "$tmp" ]; then
    # Trim the transparent squircle margin macOS bakes into .icns, then re-pad a
    # tiny uniform amount and resize back to a fixed square so every app icon
    # fills the same visual box (kills the "small icon floating in big pill" jank
    # and keeps multi-icon strips evenly spaced).
    if command -v magick >/dev/null 2>&1; then
      magick "$tmp" -trim +repage \
        -resize "${ICON_PX}x${ICON_PX}" \
        -background none -gravity center -extent "${ICON_PX}x${ICON_PX}" \
        "png:$tmp" >/dev/null 2>&1
    fi
    mv -f "$tmp" "$out" 2>/dev/null && return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

# resolve_app_icon <bundle-id>
# Echoes an absolute PNG path (cached app icon, or generic fallback).
resolve_app_icon() {
  local bid="$1"
  [ -z "$bid" ] && { printf '%s' "$GENERIC_ICON"; return; }

  local out="$ICON_CACHE/$(_safe "$bid").png"
  if [ -f "$out" ]; then printf '%s' "$out"; return; fi

  # Resolve .app bundle path from bundle id
  local app
  app=$(mdfind "kMDItemCFBundleIdentifier == '$bid'" 2>/dev/null | head -1)
  if [ -z "$app" ] || [ ! -d "$app" ]; then
    printf '%s' "$GENERIC_ICON"; return
  fi

  if _icns_to_png "$app" "$out"; then printf '%s' "$out"; return; fi
  printf '%s' "$GENERIC_ICON"
}

# resolve_app_icon_by_name <app display name>
# Resolve an app icon by its display name (e.g. "Google Chrome"). Uses mdfind on
# kMDItemDisplayName / kMDItemFSName, then Spotlight app search. Cached by name.
resolve_app_icon_by_name() {
  local name="$1"
  [ -z "$name" ] && { printf '%s' "$GENERIC_ICON"; return; }

  local out="$ICON_CACHE/name_$(_safe "$name").png"
  if [ -f "$out" ]; then printf '%s' "$out"; return; fi

  local app
  # Prefer exact .app filename match under standard locations.
  app=$(mdfind "kMDItemContentType == 'com.apple.application-bundle' && kMDItemFSName == '$name.app'" 2>/dev/null | head -1)
  [ -z "$app" ] && app=$(mdfind "kMDItemKind == 'Application' && kMDItemDisplayName == '$name'" 2>/dev/null | head -1)
  # Common fixed locations as a last resort.
  if [ -z "$app" ] || [ ! -d "$app" ]; then
    local cand
    for cand in "/Applications/$name.app" "$HOME/Applications/$name.app" \
                "/System/Applications/$name.app"; do
      [ -d "$cand" ] && { app="$cand"; break; }
    done
  fi
  if [ -z "$app" ] || [ ! -d "$app" ]; then
    printf '%s' "$GENERIC_ICON"; return
  fi

  if _icns_to_png "$app" "$out"; then printf '%s' "$out"; return; fi
  printf '%s' "$GENERIC_ICON"
}

# build_strip <ws-id> <focused:0|1> <cap> <bundle-id> [<bundle-id> ...]
# Composites: [workspace number][gap][up to <cap> app icons] into one PNG.
# The number is baked in so it can never be hidden behind the image (SketchyBar
# draws background.image over the icon text). <focused> selects number color:
#   1 -> dark number (for the mauve focused pill), 0 -> light number.
# Echoes strip path, or empty.
build_strip() {
  local wsid="$1" focused="$2" cap="$3"; shift 3
  local bids=("$@")
  [ "${#bids[@]}" -eq 0 ] && { printf ''; return; }

  local numcolor="$NUM_COLOR_LIGHT"
  [ "$focused" = "1" ] && numcolor="$NUM_COLOR_DARK"

  local capped=("${bids[@]:0:$cap}")

  # Cache key includes everything that affects the pixels (incl. number color)
  local key
  key=$(_fast_hash "${ICON_PX}:${NUM_PT}:${NUM_GAP}:${numcolor}:${wsid}:${capped[*]}")
  local strip="$STRIP_CACHE/$key.png"
  if [ -f "$strip" ]; then printf '%s|%s' "$strip" "$(_strip_px_w "$strip")"; return; fi

  # Resolve each icon to a PNG path
  local pngs=() b p
  for b in "${capped[@]}"; do
    p=$(resolve_app_icon "$b")
    [ -n "$p" ] && [ -f "$p" ] && pngs+=("$p")
  done
  [ "${#pngs[@]}" -eq 0 ] && { printf ''; return; }

  # Render the number label to a temp PNG (.png suffix so IM infers format;
  # also force with png: prefix for safety).
  local numtmp="$strip.num.$$.png"
  local fontarg=()
  [ -n "$NUM_FONT" ] && fontarg=( -font "$NUM_FONT" )
  # Render number then force its canvas to ICON_PX tall so center-gravity append
  # aligns the number's optical middle with the icons (no more high-riding digit).
  if ! magick -background none "${fontarg[@]}" -fill "$numcolor" \
        -pointsize "$NUM_PT" "label:$wsid" \
        -trim +repage -background none -gravity center -extent "x${ICON_PX}" \
        "png:$numtmp" >/dev/null 2>&1; then
    numtmp=""  # number render failed; proceed icons-only
  fi

  # Composite [number][gap][icons] horizontally, vertically centered, then add a
  # symmetric transparent edge margin so the number/icons never glue to the pill
  # border and the strip sits centered inside the colored fill.
  local tmp="$strip.tmp.$$.png"
  local edge="${SPACESUIT_STRIP_EDGE:-12}"  # retina px each side (2x -> ~6px visual)
  local ok=1
  local inputs=()
  if [ -n "$numtmp" ] && [ -s "$numtmp" ]; then
    # Create a transparent spacer image for the gap between number and icons
    local gaptmp="$strip.gap.$$.png"
    magick -size "${NUM_GAP}x${ICON_PX}" xc:none "png:$gaptmp" >/dev/null 2>&1
    inputs=( "$numtmp" "$gaptmp" "${pngs[@]}" )
  else
    inputs=( "${pngs[@]}" )
  fi
  # 1) append number+icons  2) west splice (left margin)  3) east splice (right
  #    margin). Each splice needs its own -gravity BEFORE it or it inserts at the
  #    prior gravity (was center -> broke the margin entirely).
  magick "${inputs[@]}" +append -background none \
    -gravity west -splice "${edge}x0" \
    -gravity east -splice "${edge}x0" +repage \
    "png:$tmp" >/dev/null 2>&1 || ok=0
  rm -f "$numtmp" "$strip.gap.$$.png" 2>/dev/null

  if [ "$ok" -eq 1 ] && [ -s "$tmp" ]; then
    mv -f "$tmp" "$strip" 2>/dev/null || { rm -f "$tmp"; printf ''; return; }
    # Write sidecar width file for instant reads on the hot path
    local pw; pw=$(_strip_px_w "$strip")
    printf '%s' "$pw" > "${strip}.w"
    printf '%s|%s' "$strip" "$pw"; return
  fi
  rm -f "$tmp" 2>/dev/null
  printf ''
}

# (pixel-width reader is defined above as _strip_px_w — reads PNG header directly)

# Point size for the app name baked into top-5 strips.
TOP_LABEL_PT="${SPACESUIT_TOP_LABEL_PT:-22}"
TOP_LABEL_COLOR="${SPACESUIT_TOP_LABEL_COLOR:-#a6adc8}"

# build_top_strip <index-digit> <app display name> [short label]
# Composites [index][gap][app icon][gap][name] into ONE PNG for the alt-o
# top-5 items. Baking everything into a single image guarantees uniform
# spacing (no SketchyBar image-vs-label reservation conflict). Index + name
# use light colors (these pills are never mauve).
# Echoes "path|pixel_width", or empty on failure.
build_top_strip() {
  local idx="$1" appname="$2" short="${3:-}"
  [ -z "$appname" ] && { printf ''; return; }

  local numcolor="$NUM_COLOR_LIGHT"
  local key
  key=$(_fast_hash "top2:${ICON_PX}:${NUM_PT}:${NUM_GAP}:${TOP_LABEL_PT}:${numcolor}:${TOP_LABEL_COLOR}:${idx}:${appname}:${short}")
  local strip="$STRIP_CACHE/$key.png"
  if [ -f "$strip" ]; then printf '%s|%s' "$strip" "$(_strip_px_w "$strip")"; return; fi

  local png
  png=$(resolve_app_icon_by_name "$appname")
  [ -n "$png" ] && [ -f "$png" ] || { printf ''; return; }

  local fontarg=()
  [ -n "$NUM_FONT" ] && fontarg=( -font "$NUM_FONT" )

  # Index digit
  local numtmp="$strip.num.$$.png"
  if ! magick -background none "${fontarg[@]}" -fill "$numcolor" \
        -pointsize "$NUM_PT" "label:$idx" "png:$numtmp" >/dev/null 2>&1; then
    numtmp=""
  fi
  # App name text (optional — only when a short label is supplied)
  local lbltmp=""
  if [ -n "$short" ]; then
    lbltmp="$strip.lbl.$$.png"
    if ! magick -background none "${fontarg[@]}" -fill "$TOP_LABEL_COLOR" \
          -pointsize "$TOP_LABEL_PT" "label:$short" "png:$lbltmp" >/dev/null 2>&1; then
      lbltmp=""
    fi
  fi

  # Assemble pieces left-to-right with a fixed gap between each.
  local parts=()
  [ -n "$numtmp" ] && [ -s "$numtmp" ] && parts+=( "$numtmp" -background none -splice "${NUM_GAP}x0" )
  parts+=( "$png" )
  [ -n "$lbltmp" ] && [ -s "$lbltmp" ] && parts+=( -background none -splice "${NUM_GAP}x0" "$lbltmp" )

  local tmp="$strip.tmp.$$.png"
  local ok=1
  magick "${parts[@]}" +append -background none -gravity center "png:$tmp" \
    >/dev/null 2>&1 || ok=0
  rm -f "$numtmp" "$lbltmp" 2>/dev/null

  if [ "$ok" -eq 1 ] && [ -s "$tmp" ]; then
    mv -f "$tmp" "$strip" 2>/dev/null || { rm -f "$tmp"; printf ''; return; }
    local pw; pw=$(_strip_px_w "$strip")
    printf '%s' "$pw" > "${strip}.w"
    printf '%s|%s' "$strip" "$pw"; return
  fi
  rm -f "$tmp" 2>/dev/null
  printf ''
}

# icons_clear — wipe both caches (used by `spacesuit icons --rebuild`)
icons_clear() {
  rm -rf "$ICON_CACHE" "$STRIP_CACHE" 2>/dev/null
  mkdir -p "$ICON_CACHE" "$STRIP_CACHE" 2>/dev/null
}
