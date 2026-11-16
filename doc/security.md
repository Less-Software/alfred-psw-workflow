# Security

Everything the workflow does to keep your passwords safe, and what it can't protect against.

## What is stored, and where

| File | Contents | Mode |
|------|----------|------|
| Login keychain (`~/Library/Keychains/login.keychain-db`), item `alfred-psw-workflow` | 32 random bytes, hex-encoded: the secret behind the cache key | encrypted with your login keychain password |
| `~/.cache/alfred-psw-workflow/apw_cache.enc` | The title, domain and username of each entry, encrypted | `600` |
| `~/Library/LaunchAgents/sh.less-software.psw-workflow.apw-auth.plist` | The paths of the agent script and of this plist, and your `$PATH` | default |

The workflow never writes passwords, OTP codes, notes or the `apw` PIN to disk.

## Exporting Passwords.csv

Export Passwords.csv to a RAM disk, so it never touches your disk.
[RAM Folder](https://less-software.sh/ram-folder) is a modern, reliable way to do this:
create a RAM Folder with **Sync RAM Folder** turned off, save the export there, and select it in the `pswsetup`
file picker.

Otherwise, you'll find every alternative method available to create a RAM Disk on macOS in this
[macOS RAM Disk guide](https://less-software.sh/ram-folder/macos-ram-disk) (just enable encryption 
when creating the disk image).

Instead, you can use an external hard disk (HDD, not an SSD or USB stick) that isn't indexed by Spotlight, isn't 
backed up by Time Machine, and is formatted Mac OS Extended or exFAT, so that no APFS snapshot keeps a copy of the file.
On flash storage, overwriting doesn't reach the original data, whatever the format.

If you export to a regular folder instead, be sure to exclude it from Time Machine backups and from Spotlight
indexing in System Settings.

## Importing Passwords.csv (`pswsetup`)

Passwords.csv holds every password in clear text, so `pswsetup` keeps as little of it as possible, for as short a
time as possible:

- The file picker only accepts CSV files.
- Only the Title, URL and Username columns are kept: Password, Notes and OTPAuth never are.
- Each URL is reduced to its host, plus its port when it isn't the default one: paths and query strings are never kept.
- Once the file is known to be a Passwords export, it is overwritten with zeros, synced to disk, then deleted when
  `pswsetup` exits, however it ends: success, parsing error, unreadable seed or unexpected error.
  If it can't be overwritten (a read-only file, for example), it is still deleted.
- A CSV without a `Password` column isn't a Passwords export: it is left untouched, so picking the wrong file can't
  destroy it.

On an SSD, the overwrite doesn't guarantee the data is gone (see [Limits](#limits)): export to a RAM disk instead.

## Search cache encryption

- The cache is encrypted with `AES-256-CBC`, with a new random IV at each `pswsetup`.
- The key is derived with `PBKDF2-HMAC-SHA1` (10,000 iterations, 32 bytes) from:
  - the seed: 256 random bits from Ruby's `SecureRandom`, created once and never overwritten. It is stored in your
    login keychain, which is encrypted with your login keychain password (normally your Mac login password), and
    reaches it through the standard input of `security`, never in a command line. Being random, it can't be guessed,
    whatever the iteration count.
  - a salt made of the **Cipher Salt** [configuration variable](../README.md#configuration-variables) and this Mac's
    hardware UUID (`IOPlatformUUID`). The UUID binds the cache to this Mac: a copy of the seed and the cache can't
    be decrypted on another Mac.
- The cache is written to a temporary file with mode `600` from the start, then renamed over the previous one: it is
  never readable by others, and a failed write keeps the previous cache.
- `psw` decrypts the cache in memory at each search: its decrypted content is never written to disk.

## Copying a password or OTP code

- Passwords and OTP codes are fetched live from **Apple Passwords** through [`apw`](https://github.com/bendews/apw), and
  need Touch ID (or your password) to unlock each entry.
- The workflow copies the first result whose username exactly matches the selected entry's: `apw` can return several
  accounts for a website, and the workflow never copies another account's password.
- For an entry without a website, which `apw` can't look up, the workflow opens **Passwords.app** instead of guessing.
- The secret goes from `apw` to the clipboard through pipes only: never in a command-line argument (which other
  processes can read), a file, a notification or the scripts' output (which Alfred's debugger shows).
- Notifications show fixed messages, such as "Password copied to clipboard!", never the secret.
- Alfred passes the query and the selected entry to the scripts as arguments, never pasted into their code, and the
  username reaches `jq` with `--arg`: a query or username with quotes or shell characters can't run commands.

## Secure clipboard

- The copy is marked concealed and transient ([nspasteboard.org](http://nspasteboard.org)): clipboard managers that
  respect these markers don't record it.
- It is limited to this Mac: it stays off Universal Clipboard, so it isn't sent to your other Apple devices.
- The clipboard is cleared 30 seconds after the copy (**Keep Clipboard Delay** in the
  [configuration](../README.md#configuration-variables)), unless something else was copied meanwhile: the workflow
  never erases what you copied since.
- The delay is checked before copying: a value that isn't a number makes the copy fail, rather than leave the secret
  on the clipboard.
- The background job that clears the clipboard holds only the clipboard's change count, never the secret.
- A failed clipboard write is reported as an error, never as a successful copy.

## `apw` authentication (Launch Agent)

- The agent runs as you (a LaunchAgent, not a system-wide daemon), at login and every 15 minutes.
- It checks whether `apw` is authenticated by looking up `example.invalid`, a reserved domain that can't match any
  entry: the check never fetches a password.
- The PIN is asked in a macOS dialog, checked to be 6 digits, and written to the prompt of `apw auth` through a
  pipe: it never appears in a command line, which other processes can read, and is never stored.
  **Apple Passwords** shows a new one at each request.
- The values written to the plist are XML-escaped, so an unusual path can't change what the agent runs.
- To remove the agent, uncheck **APW Launch Agent** in the [configuration](../README.md#configuration-variables) and
  run `pswsetup`. If you delete the workflow, the agent detects at its next run (within 15 minutes, or at the next
  login) that its script is gone, and uninstalls itself: it deletes its plist and unloads itself from launchd.

## Tests

The tests use fake `HOME` and `PATH` folders, throwaway keychains and a private pasteboard: they never touch your real
seed, cache, clipboard or Passwords. Creating a throwaway keychain adds it to your keychain search list: the tests
restore the list right away.

## Limits

- **Passwords.csv on disk:** before `pswsetup` deletes it, Spotlight can index the export and Time Machine can back
  it up. On an SSD, overwriting doesn't reach the original data, as the drive writes to new cells, and APFS snapshots
  can keep it too. Apple no longer offers a secure delete for SSDs and
  [recommends FileVault instead](https://support.apple.com/guide/disk-utility/erase-and-reformat-a-storage-device-dskutl14079/mac):
  [export to a RAM disk](#exporting-to-a-ram-disk), and turn on FileVault.
- **Software running as you** can read the seed, the hardware UUID and the cache like `psw` does, and so decrypt the
  titles, domains and usernames: the keychain lets `/usr/bin/security` read the seed without a prompt, and any
  program can run it. It can also read the clipboard while a password is on it.
- **The hardware UUID isn't secret:** System Information shows it. A backup holds the cache and your login keychain:
  anyone who also knows your login keychain password can decrypt it.
- **Clipboard managers that ignore the nspasteboard.org markers** still record the copy.
