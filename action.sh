#!/bin/bash

# $@ contains "username|domain" passed from Alfred
IFS='|' read -r USERNAME DOMAIN <<< "$@"

# Fallback clean-up in case leading/trailing spaces crept in
USERNAME=$(echo "$USERNAME" | xargs)
DOMAIN=$(echo "$DOMAIN" | xargs)

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

# Parse the JSON response using jq to extract the first result's password
PASSWORD=$(echo "$APW_JSON_OUTPUT" | "$JQ" -r '.results[0].password // empty' | tr -d '\n')

if [ $? -ne 0 ] || [ -z "$PASSWORD" ] || [ "$PASSWORD" = "null" ]; then
  osascript -e 'display notification "Failed to parse password from JSON" with title "Error"'
elif printf '%s' "$PASSWORD" | "$(dirname "$0")/copy_secret.sh"; then
  osascript -e 'display notification "Password copied to clipboard!" with title "Apple Passwords"'
else
  osascript -e 'display notification "Failed to copy to clipboard" with title "Error"'
fi
