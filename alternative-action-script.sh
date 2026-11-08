#!/bin/bash

# $@ contains "username|domain" passed from Alfred
IFS='|' read -r USERNAME DOMAIN <<< "$@"

# Fallback clean-up in case leading/trailing spaces crept in
USERNAME=$(echo "$USERNAME" | xargs)
DOMAIN=$(echo "$DOMAIN" | xargs)

APW_JSON_OUTPUT=$(/opt/homebrew/bin/apw otp get "$DOMAIN")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$APW_JSON_OUTPUT" ]; then
  osascript -e 'display notification "apw execution failed or canceled" with title "Error"'
  exit 1
fi

# /usr/bin/jq ships with macOS 15+; first entry whose username matches
OTP=$(echo "$APW_JSON_OUTPUT" | /usr/bin/jq -r --arg u "$USERNAME" \
  'first(.results[]? | select(.username == $u) | .code) // empty')

if [ -n "$OTP" ]; then
  echo -n "$OTP" | pbcopy
  osascript -e 'display notification "OTP copied to clipboard!" with title "Apple Passwords"'
else
  osascript -e 'display notification "No OTP found for this username" with title "Error"'
fi
