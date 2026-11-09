# Sourced by action.sh and alternative_action.sh with $1 = "username|domain" from Alfred.

# A domain never contains '|', so split on the last one: a username may contain '|' or quotes
USERNAME="${1%|*}"
DOMAIN="${1##*|}"

APW="$(brew --prefix apw)/bin/apw"

# Prefer system jq (macOS 15+), then Homebrew's
JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ="$(brew --prefix jq)/bin/jq"
if [ ! -x "$JQ" ]; then
  osascript -e 'display notification "jq not found: brew install jq" with title "Error"'
  exit 1
fi

# Usage: copy_from_apw <field> <label> <apw args...>
# Runs apw and copies <field> of the first result whose username is USERNAME (apw can return several accounts).
# <label> is our own constant, so it is safe inside the AppleScript source.
copy_from_apw() {
  local field=$1 label=$2 json value
  shift 2
  json=$("$APW" "$@")
  if [ $? -ne 0 ] || [ -z "$json" ]; then
    osascript -e 'display notification "apw execution failed or canceled" with title "Error"'
    exit 1
  fi

  value=$(printf '%s' "$json" | "$JQ" -r --arg u "$USERNAME" --arg f "$field" \
    'first(.results[]? | select(.username == $u) | .[$f] | strings) // empty')

  if [ -z "$value" ]; then
    osascript -e "display notification \"No $label found for this username\" with title \"Error\""
  elif printf '%s' "$value" | "$(dirname "$0")/copy_secret.sh"; then
    osascript -e "display notification \"$label copied to clipboard!\" with title \"Apple Passwords\""
  else
    osascript -e 'display notification "Failed to copy to clipboard" with title "Error"'
  fi
}
