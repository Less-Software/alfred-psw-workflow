#!/bin/bash

# $1 is "username|domain" from Alfred. A domain never contains '|', so split on the last one:
# a username may contain '|' or quotes
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

# Call apw with domain and username
APW_JSON_OUTPUT=$("$APW" pw get "$DOMAIN" "$USERNAME")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$APW_JSON_OUTPUT" ]; then
  osascript -e 'display notification "apw execution failed or canceled" with title "Error"'
  exit 1
fi

# First entry whose username matches: apw can return several accounts for a domain
PASSWORD=$(echo "$APW_JSON_OUTPUT" | "$JQ" -r --arg u "$USERNAME" \
  'first(.results[]? | select(.username == $u) | .password) // empty')

if [ -z "$PASSWORD" ]; then
  osascript -e 'display notification "No Password found for this username" with title "Error"'
elif printf '%s' "$PASSWORD" | "$(dirname "$0")/copy_secret.sh"; then
  osascript -e 'display notification "Password copied to clipboard!" with title "Apple Passwords"'
else
  osascript -e 'display notification "Failed to copy to clipboard" with title "Error"'
fi
