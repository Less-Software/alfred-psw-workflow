#!/bin/bash
# Run at login and every 15 minutes by the LaunchAgent pswsetup installs (see generate_launch_agent.rb).
# The apw daemon loses its session when it restarts: authenticate it again with the PIN Apple Passwords shows.

# Bring the installed agent up to date with this workflow version. Reloading a changed agent ends this run,
# and the new agent runs at once.
"$(brew --prefix ruby)/bin/ruby" "$(dirname "$0")/generate_launch_agent.rb"

APW="$(brew --prefix apw)/bin/apw"

# Open the user's Chrome. apw's daemon runs its own headless Chrome: its processes use an .apw profile, except
# its crashpad handler, so only another process from Chrome's bundle is the user's Chrome.
# -n: macOS counts apw's Chrome as running, so plain `open -a` would only bring it to the front.
pgrep -lf "Google Chrome.app" | grep -Fv /.apw/ | grep -qv Crashpad || open -n -g -a "Google Chrome"

# Status 9: apw is not running or not authenticated. Any other status (results or none) means it is.
"$APW" pw list example.invalid >/dev/null 2>&1
[ $? -eq 9 ] || exit 0

# No daemon to authenticate with: tell the user how to start it (shown at each run until it runs)
if ! pgrep -qf "apw start"; then
  osascript -e 'on run {message}' -e 'activate' \
    -e 'set answer to display dialog message with title "Passwords.app Workflow" with icon caution ¬
      buttons {"Open Documentation", "OK"} default button "OK"' \
    -e 'if button returned of answer is "Open Documentation" then ¬
      open location "https://github.com/bendews/apw#getting-started"' \
    -e 'end run' "The apw daemon isn't running, so passwords and OTP codes can't be copied. Start it in Terminal:

• Homebrew install: brew services start apw
• Custom install: apw start" >/dev/null
  exit 0
fi

prompt="Enter the PIN shown by Apple Passwords to authenticate apw:"
# Each request makes Apple Passwords show a new PIN; launchd won't start another run while this one waits
while "$APW" auth request >/dev/null; do
  pin=$(osascript -e 'on run {prompt}' -e 'activate' \
    -e 'text returned of (display dialog prompt default answer "" with title "Passwords.app Workflow")' \
    -e 'end run' "$prompt") || exit 0 # canceled: ask again at the next run
  pin=${pin//[[:space:]]/}
  [[ $pin =~ ^[0-9]{6}$ ]] && "$APW" auth response --pin "$pin" >/dev/null && exit 0
  prompt="Wrong PIN. Enter the new PIN shown by Apple Passwords:"
done
