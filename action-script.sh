#!/bin/bash

# $@ contains "username|domain" passed from Alfred
IFS='|' read -r USERNAME DOMAIN <<< "$@"

# Fallback clean-up in case leading/trailing spaces crept in
USERNAME=$(echo "$USERNAME" | xargs)
DOMAIN=$(echo "$DOMAIN" | xargs)

# Call apw with domain and username
APW_JSON_OUTPUT=$(/opt/homebrew/bin/apw pw get "$DOMAIN" "$USERNAME")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$APW_JSON_OUTPUT" ]; then
  osascript -e 'display notification "apw execution failed or canceled" with title "Error"'
  exit 1
fi

# Parse the JSON response using yq to extract the first result's password
PASSWORD=$(echo "$APW_JSON_OUTPUT" | /opt/homebrew/bin/yq '.results[0].password' | tr -d '\n')

if [ $? -eq 0 ] && [ -n "$PASSWORD" ] && [ "$PASSWORD" != "null" ]; then
  echo -n "$PASSWORD" | pbcopy
  osascript -e 'display notification "Password copied to clipboard!" with title "Apple Passwords"'
else
  osascript -e 'display notification "Failed to parse password from JSON" with title "Error"'
fi
