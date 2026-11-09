# Sourced by action.sh and alternative_action.sh with $1 = "username|domain" from Alfred.
# stdout goes to Alfred's Post Notification output (which shows the workflow icon): print exactly one notify.

# Messages and titles are our own constants, without quotes or backslashes, so they need no JSON escaping
notify() {
  printf '{"alfredworkflow":{"arg":"%s","variables":{"notification_title":"%s"}}}\n' "$1" "$2"
}

# A domain never contains '|', so split on the last one: a username may contain '|' or quotes
USERNAME="${1%|*}"
DOMAIN="${1##*|}"

APW="$(brew --prefix apw)/bin/apw"

# Errors exit 0: Alfred may not run the notification after a failed script
# Prefer system jq (macOS 15+), then Homebrew's
JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ="$(brew --prefix jq)/bin/jq"
if [ ! -x "$JQ" ]; then
  notify "jq not found: brew install jq" Error
  exit 0
fi

# Usage: copy_from_apw <field> <label> <apw args...>
# Runs apw and copies <field> of the first result whose username is USERNAME (apw can return several accounts).
copy_from_apw() {
  local field=$1 label=$2 json value
  shift 2
  json=$("$APW" "$@")
  if [ $? -ne 0 ] || [ -z "$json" ]; then
    notify "apw execution failed or canceled" Error
    exit 0
  fi

  value=$(printf '%s' "$json" | "$JQ" -r --arg u "$USERNAME" --arg f "$field" \
    'first(.results[]? | select(.username == $u) | .[$f] | strings) // empty')

  if [ -z "$value" ]; then
    notify "No $label found for this username" Error
  elif printf '%s' "$value" | "$(dirname "$0")/copy_secret.sh"; then
    notify "$label copied to clipboard!" "Apple Passwords"
  else
    notify "Failed to copy to clipboard" Error
  fi
}
