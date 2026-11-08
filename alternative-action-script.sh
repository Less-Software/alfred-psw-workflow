# {query} contains "username::url" passed from Alfred
IFS='::' read -r USERNAME DOMAIN <<< "{query}"

# Call apw to retrieve OTP (adjust flag if needed, e.g., --otp)
OTP=$(apw get --otp "$DOMAIN" "$USERNAME")

if [ $? -eq 0 ] && [ -n "$OTP" ]; then
  echo -n "$OTP" | pbcopy
  osascript -e 'display notification "OTP copied to clipboard!" with title "Apple Passwords"'
else
  osascript -e 'display notification "Failed to retrieve OTP" with title "Error"'
fi