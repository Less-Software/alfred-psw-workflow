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
