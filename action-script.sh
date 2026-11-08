#!/bin/bash

# $@ contains "username|domain" passed from Alfred
IFS='|' read -r USERNAME DOMAIN <<< "$@"

# Fallback clean-up in case leading/trailing spaces crept in
USERNAME=$(echo "$USERNAME" | xargs)
DOMAIN=$(echo "$DOMAIN" | xargs)

# Alfred has no user $PATH: prefer system jq (macOS 15+), then Homebrew (Apple Silicon, Intel)
for JQ in /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq ""; do
  [ -x "$JQ" ] && break
done
if [ -z "$JQ" ]; then
  osascript -e 'display notification "jq not found: brew install jq" with title "Error"'
  exit 1
fi

# Call apw with domain and username
APW_JSON_OUTPUT=$(/opt/homebrew/bin/apw pw get "$DOMAIN" "$USERNAME")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$APW_JSON_OUTPUT" ]; then
  osascript -e 'display notification "apw execution failed or canceled" with title "Error"'
  exit 1
fi

# Parse the JSON response using jq to extract the first result's password
PASSWORD=$(echo "$APW_JSON_OUTPUT" | "$JQ" -r '.results[0].password // empty' | tr -d '\n')

if [ $? -eq 0 ] && [ -n "$PASSWORD" ] && [ "$PASSWORD" != "null" ]; then
  echo -n "$PASSWORD" | pbcopy
  osascript -e 'display notification "Password copied to clipboard!" with title "Apple Passwords"'
else
  osascript -e 'display notification "Failed to parse password from JSON" with title "Error"'
fi
