#!/bin/bash
# Run at login and every 15 minutes by the LaunchAgent pswsetup installs (see generate.rb).
# The apw daemon loses its session when it restarts: authenticate it again with the PIN Apple Passwords shows.

# Bring the installed agent up to date with this workflow version. Reloading a changed agent ends this run,
# and the new agent runs at once.
"$(brew --prefix ruby)/bin/ruby" "$(dirname "$0")/generate.rb"

APW="$(brew --prefix apw)/bin/apw"

# Status 9: apw is not running or not authenticated. Any other status (results or none) means it is.
"$APW" pw list example.invalid >/dev/null 2>&1
[ $? -eq 9 ] || exit 0

# Makes Apple Passwords show a new PIN. The daemon may still be starting (at login): retry for 30 seconds, then
# tell the user how to (re)start it, at each run until it answers.
request_pin() {
  for _ in 1 2 3 4 5 6; do
    "$APW" auth request >/dev/null && return
    sleep 5
  done
  osascript -e 'on run {message}' -e 'activate' \
    -e 'set answer to display dialog message with title "Passwords.app Workflow" with icon caution ¬
      buttons {"Open Documentation", "OK"} default button "OK"' \
    -e 'if button returned of answer is "Open Documentation" then ¬
      open location "https://github.com/bendews/apw#getting-started"' \
    -e 'end run' "The apw daemon isn't running or isn't responding, so passwords and OTP codes can't be copied. \
Restart it in Terminal:

• Homebrew install: brew services restart apw
• Custom install: apw start" >/dev/null
  return 1
}

prompt="Enter the PIN shown by Apple Passwords to authenticate apw:"
# launchd won't start another run while this one waits
while request_pin; do
  pin=$(osascript -e 'on run {prompt}' -e 'activate' \
    -e 'text returned of (display dialog prompt default answer "" with title "Passwords.app Workflow")' \
    -e 'end run' "$prompt") || exit 0 # canceled: ask again at the next run
  pin=${pin//[[:space:]]/}
  [[ $pin =~ ^[0-9]{6}$ ]] && "$APW" auth response --pin "$pin" >/dev/null && exit 0
  prompt="Wrong PIN. Enter the new PIN shown by Apple Passwords:"
done
