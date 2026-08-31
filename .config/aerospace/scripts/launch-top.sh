#!/opt/homebrew/bin/bash
# Launch top N app (called with arg 1-5)

BIND_FILE="$HOME/.config/aerospace/usage/top5.sh"
[ ! -f "$BIND_FILE" ] && exit 0

source "$BIND_FILE"

N="$1"
case "$N" in
  1) eval "$TOP_CMD_1" 2>/dev/null ;;
  2) eval "$TOP_CMD_2" 2>/dev/null ;;
  3) eval "$TOP_CMD_3" 2>/dev/null ;;
  4) eval "$TOP_CMD_4" 2>/dev/null ;;
  5) eval "$TOP_CMD_5" 2>/dev/null ;;
esac
