#!/bin/bash
# Run at login and every 15 minutes by the LaunchAgent pswsetup installs (see generate.rb).
# The apw daemon loses its session when it restarts: authenticate it again with the PIN Apple Passwords shows.

# Bring the installed agent up to date with this workflow version. Reloading a changed agent ends this run,
# and the new agent runs at once.
"$(brew --prefix ruby)/bin/ruby" "$(dirname "$0")/generate.rb"

APW="$(brew --prefix apw)/bin/apw"

# apw answers {"error":"unpaired",…} when the daemon runs but isn't authenticated, and {"results":[…],…} when it is.
# Any other answer: the daemon isn't running, or is still starting (at login). Retry for 30 seconds, then tell
# the user how to (re)start it, at each run until it answers.
wait_for_daemon() {
  for _ in 1 2 3 4 5 6; do
    case $("$APW" pw list example.invalid 2>&1) in
      *'"error":"unpaired"'*) return ;;
      *'"error"'*) ;; # errors include "results" too
      *'"results"'*) exit 0 ;; # authenticated
    esac
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
  exit 0
}
wait_for_daemon

# `apw auth` makes Apple Passwords show a new PIN, then prompts for it on stdin. The PIN goes there through a FIFO,
# never in a command line, which other processes can read. launchd won't start another run while this one waits.
fifos=$(mktemp -d) && mkfifo "$fifos/in" "$fifos/out" || exit 0
trap 'rm -rf "$fifos"' EXIT
prompt="Enter the PIN shown by Apple Passwords to authenticate apw:"
while :; do
  "$APW" auth <"$fifos/in" >"$fifos/out" &
  apw=$!
  exec 3>"$fifos/in" 4<"$fifos/out"
  # apw exits without prompting when the request fails: the next run tries again
  while IFS= read -r -d : -u 4 text && [[ $text != *'Enter PIN' ]]; do :; done
  [[ $text == *'Enter PIN' ]] || exit 0

  pin=$(osascript -e 'on run {prompt}' -e 'activate' \
    -e 'text returned of (display dialog prompt default answer "" with title "Passwords.app Workflow")' \
    -e 'end run' "$prompt") || { kill "$apw"; exit 0; } # canceled: ask again at the next run
  pin=${pin//[[:space:]]/}
  if [[ $pin =~ ^[0-9]{6}$ ]]; then
    printf '%s\r' "$pin" >&3 # printf is a builtin: no command line holds the PIN
    cat <&4 >/dev/null # apw echoes the PIN: keep reading until it exits, or its writes would fail
    wait "$apw" && exit 0
  else
    kill "$apw" # before closing its stdin: apw's prompt spins on end of input
  fi
  exec 3>&- 4<&-
  prompt="Wrong PIN. Enter the new PIN shown by Apple Passwords:"
done
