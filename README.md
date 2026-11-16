# alfred-psw-workflow (macOS only)

<img width="64" height="64" alt="alfred-psw-icon" src="https://github.com/user-attachments/assets/a4cc102f-93ef-4811-b29a-db2288846162"><br>
<a href="https://github.com/Less-Software/alfred-psw-workflow/actions/workflows/test.yml"><img alt="Test" src="https://github.com/Less-Software/alfred-psw-workflow/actions/workflows/test.yml/badge.svg"></a>

Alfred workflow that lets you search Apple **Passwords.app** entries and copy a password (main action) or OTP code
(alternative action) to *a secure, expiring clipboard*.

Searching uses a pre-computed local encrypted cache of titles, domains and usernames (never passwords).
This cache is created from a **Passwords.csv** export from **Passwords.app**, and imported via `pswsetup`.

Passwords and OTP codes are fetched live from **Apple Passwords** through [`apw`](https://github.com/bendews/apw),
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
unless you copied something else meanwhile (see [Secure clipboard](doc/security.md#secure-clipboard)).

`apw` finds entries by website, so for an entry without one, ↩ and ⌥↩ open **Passwords.app** instead.

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

Then set up `apw`: you'll need a compatible browser (Chrome will do) with the
[iCloud Passwords extension](https://chromewebstore.google.com/detail/icloud-passwords/pejdijmoenmkgeppbflobdenhhabjlaj?hl=en) installed and the `apw` background daemon installed & running).

By following the [`apw` Getting Started guide](https://github.com/bendews/apw#getting-started).
`apw auth` must be run again every time the daemon restarts (for example after a reboot):
`pswsetup` can install a launch agent that does it for you.

The scripts find Homebrew's `ruby`, `apw` and `jq` with `brew --prefix <formula>`, so `brew` must be on
the `$PATH` Alfred runs scripts with. The Ruby scripts start with a short `/bin/sh` launcher that re-runs
them with Homebrew's ruby, because a shebang line can't call `brew`.

### `pswsetup` command

Builds the encrypted search cache from a Passwords CSV export.
Run it once to set up, then again whenever you add, rename or delete entries in Passwords:
`psw` only finds the entries that existed at the last sync.

1. Export your passwords to a CSV file: in the **Passwords app**, **File → Export All Passwords…**
   We recommend saving it to a [RAM disk](doc/security.md#exporting-passwordscsv).
2. In Alfred, type `pswsetup` and select the CSV file in the file picker that opens.

The cache is now ready and Passwords.csv has been deleted: you can start using `psw`.

`pswsetup` also installs a LaunchAgent (`~/Library/LaunchAgents/sh.less-software.psw-workflow.apw-auth.plist`)
that runs `src/launch_agent/agent_script.sh` at login and every 15 minutes. When `apw` isn't authenticated, it
asks for the PIN shown by **Apple Passwords**. macOS doesn't let it read the workflow if Alfred's preferences are
in Documents, Desktop or a cloud folder: the agent then says so in a dialog.

To opt out, uncheck **APW Launch Agent** in the [Workflow's Configuration](#configuration-variables) and run `pswsetup` again: 
it removes the LaunchAgent. Deleting the workflow is enough too: at its next run, the LaunchAgent finds
`src/launch_agent/agent_script.sh` gone and removes itself. Workflow updates need no `pswsetup`: each run
brings the LaunchAgent up to date first.

<br>
<div align="center">
  <video src="https://github.com/user-attachments/assets/60db8913-8a09-4522-8edd-1b473578a4ae">
</div>
<br>

## Configuration variables

The following variables are configurable via Alfred:

| Name | Description | Default |
|------|-------------|---------|
| **Search Keyword** | Keyword to trigger password search | `psw` |
| **Cipher Salt** | Salt used during key-derivation process for encryption | `alfred-psw-workflow` |
| **Keep Clipboard Delay** | Number of seconds (decimals allowed) to keep password/OTP in secure clipboard | `30` |
| **APW Launch Agent** | Let `pswsetup` install the launch agent that keeps `apw` authenticated (unchecked: remove it) | checked |

## Troubleshooting

| Message | Fix |
|---------|-----|
| `The apw daemon isn't running or isn't responding…` (dialog) | Restart the daemon in Terminal: `brew services restart apw` (Homebrew install) or `apw start` (custom install). The dialog comes back every 15 minutes until it answers. |
| `macOS blocks the apw agent from reading the workflow folder…` (dialog) | Move Alfred's preferences out of Documents, Desktop or a cloud folder (Alfred Preferences → Advanced → Syncing), or uncheck **APW Launch Agent** and run `pswsetup`. |
| `apw execution failed or canceled` | Touch ID was canceled, or the `apw` daemon isn't running or paired: start it and run `apw auth` again (needed after every reboot; the **APW Launch Agent** asks for the PIN within 15 minutes). |
| `No Password found for this username` | `apw` found no password for this account, for example because it was deleted or renamed since the last sync: run `pswsetup`. |
| `No OTP found for this username` | The entry has no verification code in Passwords. |
| `jq not found: brew install jq` | Install jq (macOS < 15 only). |
| `Failed to copy to clipboard` | macOS refused the clipboard write: try again, and check the Alfred debugger for the error. |
| `Cache missing. Please run pswsetup.` | Run `pswsetup`. |
| `Decryption or Parsing Error` | The cache was made on another Mac or with another seed, the seed is missing from your login keychain, or the cache is damaged: run `pswsetup`. The subtitle shows the cause. |
| `Error: unable to parse …` (after `pswsetup`) | The CSV isn't a valid Passwords export: export it again. |
| `Error: … is not a Passwords export` (after `pswsetup`) | The picked CSV has no `Password` column, so it was left untouched: pick your Passwords export. |
| A result says `can't copy without website` | `apw` finds entries by website, so selecting an entry without one opens **Passwords.app** instead: copy it from there. |

If nothing happens at all, open the workflow in Alfred Preferences, click the debugger (🐞) icon and try
again: it shows each step and any error. A common cause is `brew` missing from the `$PATH` Alfred runs scripts with.

## Security

- Encrypted search cache, without passwords.
- Passwords and OTP codes fetched live, after Touch ID.
- Passwords.csv overwritten and deleted after import.
- Secure, expiring clipboard.
- `apw` PIN never stored.

We recommend exporting Passwords.csv to a [RAM disk](doc/security.md#exporting-passwordscsv).
See [doc/security.md](doc/security.md) for every measure in detail, and their limits.

## How it works

See [doc/files.md](doc/files.md) for what each script does.

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
