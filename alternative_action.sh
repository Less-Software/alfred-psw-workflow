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

APW_JSON_OUTPUT=$("$APW" otp get "$DOMAIN")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$APW_JSON_OUTPUT" ]; then
  osascript -e 'display notification "apw execution failed or canceled" with title "Error"'
  exit 1
fi

# First entry whose username matches
OTP=$(echo "$APW_JSON_OUTPUT" | "$JQ" -r --arg u "$USERNAME" \
  'first(.results[]? | select(.username == $u) | .code) // empty')

if [ -z "$OTP" ]; then
  osascript -e 'display notification "No OTP found for this username" with title "Error"'
elif printf '%s' "$OTP" | "$(dirname "$0")/copy_secret.sh"; then
  osascript -e 'display notification "OTP copied to clipboard!" with title "Apple Passwords"'
else
  osascript -e 'display notification "Failed to copy to clipboard" with title "Error"'
fi
