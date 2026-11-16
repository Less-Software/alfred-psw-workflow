# How it works

## `src/main.rb`: Alfred Script Filter (`psw`)

Runs on every keystroke with the query as `$1`. Once the query has at least 4 characters, it decrypts
the cache, keeps the entries whose title, domain or username contains the query, and returns them to Alfred
as Script Filter JSON. Each result's `arg` is `username|domain`.

## `src/setup_workflow.rb`: workflow setup (`pswsetup`)

Runs when invoked via `pswsetup`: it installs, updates or removes the apw auth LaunchAgent (with
`src/launch_agent/generate.rb`), then uses AppleScript to open a file picker where the user selects their
Passwords.csv export, then builds the cache from it.
You can also run it directly: `src/setup_workflow.rb path/to/Passwords.csv`.

Both Ruby scripts derive the cache key with `src/cache_key.rb`.

## `src/launch_agent/generate.rb`: apw auth LaunchAgent

Fills `src/launch_agent/sh.less-software.psw-workflow.apw-auth.plist.tpl` with the paths of
`src/launch_agent/agent_script.sh` and the plist, and the current `$PATH` (launchd's lacks Homebrew). It
writes the result to `~/Library/LaunchAgents/` and reloads the agent when the result differs from the
installed plist or launchd hasn't loaded it, or removes the agent when `APW_LAUNCH_SCRIPT` is `0`.
`setup_workflow.rb` calls it, and `agent_script.sh` runs it directly. Don't run it from a checkout in
Documents or Desktop: the agent would point at that checkout, which macOS doesn't let it read.

## `src/launch_agent/agent_script.sh`: apw authentication (LaunchAgent)

Runs `generate.rb` first, so that a workflow update that changes the template updates the installed agent: the
reload ends this run and starts the new agent. It then runs `apw pw list example.invalid`: `results` means apw
is authenticated, and the `unpaired` error means the daemon runs but isn't authenticated. Any other answer means
the daemon isn't running or is still starting (at login), so it retries for 30 seconds. If the daemon still
doesn't answer, it shows a dialog with the commands that restart it (`brew services restart apw`, or
`apw start` for a custom install) and a link to apw's Getting Started guide, and stops there. Once unpaired, it
runs `apw auth request`, asks for the PIN in an AppleScript dialog and passes it to `apw auth response --pin`,
asking again with a new PIN when it's wrong. Canceling the dialog, or a failed `apw auth request`, waits for the
next run.

## `src/actions/main.sh`: Alfred action (↩)

Receives `username|domain`, runs `apw pw get <domain> <username>`, and copies the password of the first result
whose username matches to the clipboard.

## `src/actions/alt.sh`: Alfred alternative action (⌥↩)

Receives `username|domain`, runs `apw otp get <domain>`, and copies the OTP `code` of the first result
whose username matches to the clipboard.

Both action scripts share `src/actions/apw_copy.sh`, which splits the argument on its last `|` (a username may contain one),
runs apw and copies the result. They use `/usr/bin/jq` if present, otherwise `$(brew --prefix jq)/bin/jq`.

The action scripts and `setup_workflow.rb` report the outcome (copied, or what failed) by printing it for Alfred's
Post Notification output, so notifications show the workflow icon. Their stdout holds only that message, as
`{"alfredworkflow": {"arg": "<message>", "variables": {"notification_title": "<title>"}}}`, and they exit 0 even on
errors so that Alfred still shows it.

## `src/actions/secret_pbcopy.sh`: secure copy

Called by both actions with the secret on stdin. It copies it with JavaScript for Automation (`osascript -l JavaScript`),
marked as concealed and transient and limited to this Mac, then starts a detached job that clears the clipboard
after `KEEP_CLIPBOARD_DELAY` seconds (["Keep Clipboard Delay"](../README.md#configuration-variables)) if the clipboard hasn't changed since.
