# alfred-psw-workflow (macOS only)

<img width="64" height="64" alt="alfred-psw-icon" src="https://github.com/user-attachments/assets/a4cc102f-93ef-4811-b29a-db2288846162"><br>

Alfred workflow that lets you search Apple **Passwords.app** entries and copy a password (main action) or OTP code
(alternative action) to *a secure, expiring clipboard*.

Searching uses a pre-computed local encrypted cache of titles, domains and usernames (never passwords).
This cache is created from a **Passwords.csv** export from **Password.app**, and imported via `pswsync`.

Passwords and OTP codes are fetched live from Apple Passwords through [apw](https://github.com/bendews/apw),
and require authentication before being copied (via main password or Touch ID).

## Usage

In Alfred, type `psw` followed by at least 4 characters, for example `psw github`.
You can change the `psw` keyword in the [Workflow's Configuration](#configuration-variables).

The search is case-insensitive and matches any entry whose title, domain or username contains each word of the text,
so `psw acme pass` finds "Acme Keystore Passphrase".

Results are ordered by:

1. matches in the title,
2. then matches in the domain,
3. then matches in the username,
4. then alphabetically by domain, then username.

On the selected entry:

- **↩ (Enter)** copies the password to the clipboard.
- **⌥↩ (Option-Enter)** copies the current OTP code to the clipboard.

Touch ID is then required to unlock the entry. A notification confirms the copy.
The clipboard is cleared 30 seconds later ([delay is configurable](#configuration-variables)),
unless you copied something else meanwhile (see [Security](#security)).

apw finds entries by website, so for an entry without one, ↩ and ⌥↩ open Passwords.app instead.

<br>
<div align="center">
  <img width="764" height="402" alt="'psw john' query in Alfred" src="https://github.com/user-attachments/assets/c4e9efce-2a9b-4c0a-a935-4dd9e9250f8d" />
</div>
<br>

## Setup

Install [Homebrew](https://brew.sh), then:

```sh
brew install ruby
brew install bendews/homebrew-tap/apw
brew install jq   # only on macOS < 15; macOS 15+ ships /usr/bin/jq
```

Then set up apw (a browser with the iCloud Passwords extension, the background daemon, and `apw auth` pairing)
by following the [apw Getting Started guide](https://github.com/bendews/apw#getting-started).
`apw auth` must be run again every time the daemon restarts (for example after a reboot).

The scripts find Homebrew's `ruby`, `apw` and `jq` with `brew --prefix <formula>`, so `brew` must be on
the `$PATH` Alfred runs scripts with. The Ruby scripts start with a short `/bin/sh` launcher that re-runs
them with Homebrew's ruby, because a shebang line can't call `brew`.

### `pswsync` command

Builds the encrypted search cache from a Passwords CSV export.
Run it once to set up, then again whenever you add, rename or delete entries in Passwords:
`psw` only finds the entries that existed at the last sync.

1. Export your passwords to a CSV file: in the Passwords app, **File → Export All Passwords…**
   We recommend saving it to a RAM disk (see [Security](#security)).
2. In Alfred, type `pswsync` and select the CSV file in the file picker that opens.

The cache is now ready and Passwords.csv has been deleted: you can start using `psw`.

<br>
<div align="center">
  <video src="https://github.com/user-attachments/assets/60db8913-8a09-4522-8edd-1b473578a4ae">
</div>
<br>

## Configuration variables

The following variables are configurable via Alfred:

| Name | Description | Default |
|------|-------------|---------|
| Search Keyword | Keyword to trigger password search | `psw` |
| Cipher Salt | Salt used during key-derivation process for encryption | `alfred-psw-workflow` |
| Keep Clipboard Delay | Number of seconds (decimals allowed) to keep password/OTP in secure clipboard | `30` |

## Troubleshooting

| Message | Fix |
|---------|-----|
| `apw execution failed or canceled` | Touch ID was canceled, or the apw daemon isn't running or paired: start it and run `apw auth` again (needed after every reboot). |
| `No Password found for this username` | apw found no password for this account, for example because it was deleted or renamed since the last sync: run `pswsync`. |
| `No OTP found for this username` | The entry has no verification code in Passwords. |
| `jq not found: brew install jq` | Install jq (macOS < 15 only). |
| `Failed to copy to clipboard` | macOS refused the clipboard write: try again, and check the Alfred debugger for the error. |
| `Seed or Cache missing. Please run sync.` | Run `pswsync`. |
| `Decryption or Parsing Error` | The cache was made on another Mac or with another seed, or is damaged: run `pswsync`. The subtitle shows the cause. |
| `Error: unable to parse …` (after `pswsync`) | The CSV isn't a valid Passwords export: export it again. |
| `Error: … is not a Passwords export` (after `pswsync`) | The picked CSV has no `Password` column, so it was left untouched: pick your Passwords export. |
| A result says `can't copy without website` | apw finds entries by website, so selecting an entry without one opens Passwords.app instead: copy it from there. |

If nothing happens at all, open the workflow in Alfred Preferences, click the debugger (🐞) icon and try
again: it shows each step and any error. A common cause is `brew` missing from the `$PATH` Alfred runs scripts with.

## Security

*Note:* The Passwords.csv file exported by Passwords.app contains every password in clear text.
Even though `pswsync` deletes it, a file written to your disk can be indexed by Spotlight or
copied by Time Machine before then, and deleted data can stay recoverable on the drive.

We recommend you export it to a RAM disk instead, so it never touches the disk.
[RAM Folder](https://less-software.sh/ram-folder) is a modern, reliable way to do this:
create a RAM Folder with **Sync RAM Folder** turned off, save the export there, and select it in the `pswsync`
file picker.

If you export to a regular folder instead, be sure to exclude it from Time Machine backups and from Spotlight
indexing in System Settings.

### How copied passwords are protected

Passwords and OTP codes are copied with the [nspasteboard.org](http://nspasteboard.org) concealed and transient
markers, which tell clipboard managers that respect them not to record the copy. They also stay off
Universal Clipboard, so they aren't sent to your other Apple devices.

The clipboard is cleared 30 seconds after the copy, unless something else was copied meanwhile. To change the
delay, set "Keep Clipboard Delay" in the [Workflow's Configuration](#configuration-variables). A value that isn't
a number makes the copy fail rather than leave the secret on the clipboard.

### How `pswsync` keeps my data safe

- creates `~/.config/alfred-psw-workflow/seed` (secure random, mode `600`) if it doesn't exist yet,
- derives the encryption key from that seed, the cipher customisable "salt" and this Mac's hardware UUID,
- writes the title, domain and username of each entry to `~/.cache/alfred-psw-workflow/apw_cache.enc` (mode `600`),
  for quick search when using `psw`,
- **deletes the CSV file**, even if parsing fails. A CSV without a `Password` column isn't a Passwords export:
  it is left untouched, so picking the wrong file can't delete it.

The cache can only be decrypted on the Mac that created it. If you delete the seed or move to another Mac,
run the sync again.

## How it works

### `src/main.rb`: Alfred Script Filter (`psw`)

Runs on every keystroke with the query as `$1`. Once the query has at least 4 characters, it decrypts
the cache, keeps the entries whose title, domain or username contains the query, and returns them to Alfred
as Script Filter JSON. Each result's `arg` is `username|domain`.

### `src/setup_cache.rb`: cache creation (`pswsync`)

Runs when invoked via `pswsync`: it uses AppleScript to open a file picker where the user selects their
Passwords.csv export, then builds the cache from it.
You can also run it directly: `src/setup_cache.rb path/to/Passwords.csv`.

Both Ruby scripts derive the cache key with `src/cache_key.rb`.

### `src/actions/main.sh`: Alfred action (↩)

Receives `username|domain`, runs `apw pw get <domain> <username>`, and copies the password of the first result
whose username matches to the clipboard.

### `src/actions/alt.sh`: Alfred alternative action (⌥↩)

Receives `username|domain`, runs `apw otp get <domain>`, and copies the OTP `code` of the first result
whose username matches to the clipboard.

Both action scripts share `src/actions/apw_copy.sh`, which splits the argument on its last `|` (a username may contain one),
runs apw and copies the result. They use `/usr/bin/jq` if present, otherwise `$(brew --prefix jq)/bin/jq`.

The action scripts and `setup_cache.rb` report the outcome (copied, or what failed) by printing it for Alfred's
Post Notification output, so notifications show the workflow icon. Their stdout holds only that message, as
`{"alfredworkflow": {"arg": "<message>", "variables": {"notification_title": "<title>"}}}`, and they exit 0 even on
errors so that Alfred still shows it.

### `src/actions/secret_pbcopy.sh`: secure copy

Called by both actions with the secret on stdin. It copies it with JavaScript for Automation (`osascript -l JavaScript`),
marked as concealed and transient and limited to this Mac, then starts a detached job that clears the clipboard
after `KEEP_CLIPBOARD_DELAY` seconds (["Keep Clipboard Delay"](#configuration-variables)) if the clipboard hasn't changed since.

## Contribute

- Fork https://github.com/Less-Software/alfred-psw-workflow
- Clone it to your development machine
- Add tests for your change and run `rake` before opening a pull request
- Open a pull request targeting the official repository

### Tests

```sh
rake
```

The tests run on macOS only. They use fake `HOME` and `PATH` directories, so they never touch your real
cache, clipboard or Passwords.

## License

[MIT](LICENSE)

## Sponsoring

If this workflow is useful to you, consider [sponsoring Less Software on GitHub](https://github.com/sponsors/Less-Software).

Discover more tools made with care at [less-software.sh](https://less-software.sh/).
