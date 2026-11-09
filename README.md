# alfred-pw-workflow

Alfred workflow to search Apple Passwords entries and copy a password or OTP code to the clipboard.

Searching uses a local encrypted cache of titles, domains and usernames (never passwords).
Passwords and OTP codes are fetched live from Apple Passwords through [apw](https://github.com/bendews/apw).

## Usage

In Alfred, type `pw` followed by at least 4 characters, for example `pw github`.

The search is case-insensitive and matches any entry whose title, domain or username contains the text.
Results are ordered by:

1. matches in the title,
2. then matches in the domain,
3. then matches in the username,
4. then alphabetically by domain, then username.

On the selected entry:

- **↩ (Enter)** copies the password to the clipboard.
- **⌥↩ (Option-Enter)** copies the current OTP code to the clipboard.

Touch ID is then required to unlock the entry. A notification confirms the copy.

## Dependencies

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

## Files

### `setup_cache.rb`: cache sync (run manually in Terminal)

Builds the encrypted search cache from a Passwords CSV export. Alfred never runs it.
Run it once to set up, then again whenever your passwords change:

1. Export your passwords to a CSV file: in the Passwords app, **File → Export All Passwords…**
   Save it to a RAM disk (see [Security](#security)).
2. Run:

   ```sh
   ./setup_cache.rb ~/path/to/Passwords.csv
   ```

The script:

- creates `~/.config/alfred-pw-workflow/seed` (random, mode `600`) if it doesn't exist yet,
- derives the encryption key from that seed and this Mac's hardware UUID,
- writes the title, domain and username of each entry to `~/.cache/alfred-pw-workflow/apw_cache.enc` (mode `600`),
- **deletes the CSV file**, even if parsing fails.

The cache can only be decrypted on the Mac that created it. If you delete the seed or move to another Mac,
run the sync again.

#### Security

The CSV export contains every password in clear text. Even though `setup_cache.rb` deletes it, a file
written to your disk can be indexed by Spotlight or copied by Time Machine before then, and deleted
data can stay recoverable on the drive.

Export it to a RAM disk instead, so it never touches the disk. [RAM Folder](https://less-software.sh/ram-folder)
is a modern, reliable way to do this: create a RAM Folder with **Sync RAM Folder** turned off, save the
export there, and pass that path to `setup_cache.rb`.

### `alfred_filter_script.rb`: Alfred Script Filter

Runs on every keystroke with the query as `$1`. Once the query has at least 4 characters, it decrypts
the cache, keeps the entries whose title, domain or username contains the query, and returns them to Alfred
as Script Filter JSON. Each result's `arg` is `username|domain`.

### `action.sh`: Alfred action (default)

Receives `username|domain`, runs `apw pw get <domain> <username>`, and copies the first result's password
to the clipboard.

### `alternative_action.sh`: Alfred alternative action (modifier key)

Receives `username|domain`, runs `apw otp get <domain>`, and copies the OTP `code` of the first result
whose username matches to the clipboard.

Both action scripts use `/usr/bin/jq` if present, otherwise `$(brew --prefix jq)/bin/jq`, and show a
macOS notification if jq is missing or if the lookup fails.

## Tests

```sh
rake
```

The tests run on macOS only. They use fake `HOME` and `PATH` directories, so they never touch your real
cache, clipboard or Passwords.

## Sponsoring

If this workflow is useful to you, consider [sponsoring Less Software on GitHub](https://github.com/sponsors/Less-Software).
