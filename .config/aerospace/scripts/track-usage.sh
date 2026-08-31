#!/opt/homebrew/bin/bash
# Track app/workspace usage — called on every workspace change
# Stores frequency data for adaptive launcher

USAGE_DIR="$HOME/.config/aerospace/usage"
mkdir -p "$USAGE_DIR"

USAGE_FILE="$USAGE_DIR/history.tsv"
FREQ_FILE="$USAGE_DIR/frequencies.tsv"

# Log current focus
TIMESTAMP=$(date +%s)
FOCUSED_WS=$(aerospace list-workspaces --focused 2>/dev/null)
FOCUSED_APP=$(aerospace list-windows --focused --format "%{app-name}" 2>/dev/null)
FOCUSED_TITLE=$(aerospace list-windows --focused --format "%{window-title}" 2>/dev/null)

[ -z "$FOCUSED_WS" ] && exit 0

# Append to history (keep last 5000 entries)
echo "${TIMESTAMP}	${FOCUSED_WS}	${FOCUSED_APP}	${FOCUSED_TITLE}" >> "$USAGE_FILE"
tail -5000 "$USAGE_FILE" > "$USAGE_FILE.tmp" && mv "$USAGE_FILE.tmp" "$USAGE_FILE"

# Rebuild frequency table (app frequencies)
awk -F'\t' '{print $3}' "$USAGE_FILE" | sort | uniq -c | sort -rn | awk '{print $1"\t"$2}' > "$FREQ_FILE"

# Also track time-of-day patterns (hour → app)
HOUR=$(date +%H)
HOUR_FILE="$USAGE_DIR/hour_${HOUR}.tsv"
echo "${FOCUSED_APP}	${FOCUSED_TITLE}" >> "$HOUR_FILE"
tail -500 "$HOUR_FILE" > "$HOUR_FILE.tmp" && mv "$HOUR_FILE.tmp" "$HOUR_FILE"
