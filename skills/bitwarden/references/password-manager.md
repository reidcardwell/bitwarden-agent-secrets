# Password Manager: browser login through the clipboard

Log an agent-driven browser into a site using a Bitwarden vault item. The username is not a secret and is read normally. The password goes from `bw` straight into the clipboard via `bw-fill`, is pasted into the focused field, and the clipboard is cleared at once.

## How safe this is

The clipboard bridge keeps the password out of the agent's context, but it is **weaker than Secrets Manager injection**. While the password sits on the clipboard, any app on the machine, clipboard history manager, or sync feature (Universal Clipboard, KDE Connect) can read it. `bw-fill --clear` shortens that window; it cannot close it. Use it only on a machine you control, with clipboard history and sync off, and clear immediately after every paste.

## Prerequisites

- The official `bw` CLI on `PATH`.
- `bw-token`, `bw-unlock`, `bwx` and `bw-fill` on `PATH`.
- Three secret-store entries per handle (read by `bw-token`):
  - `bw-clientid-<handle>`: API client ID
  - `bw-clientsecret-<handle>`: API client secret
  - `bw-master-<handle>`: master password
- A clipboard tool: `pbcopy` (macOS, built in), `wl-copy` (Wayland) or `xclip` (X11).
- A dedicated vault folder for agent-usable logins, written here as `<agent-folder>`. Only items in that folder are ever queried.

## Session setup

Resolve once per session. Commands below write `<H>` for the handle and `<PASTE>` for the paste chord.

| | macOS | Linux |
|---|---|---|
| Paste chord `<PASTE>` | `cmd+v` | `ctrl+v` |
| Clipboard tool (auto-selected by `bw-fill`) | `pbcopy` | `wl-copy` if `WAYLAND_DISPLAY` is set, else `xclip -selection clipboard` |

- **Confirm the handle** rather than guessing: it is the suffix of the `bw-clientid-<handle>` entry. With `pass`, list entry names (never values): `ls ~/.password-store | grep '^bw-clientid-'`.
- **Use a browser on this machine.** `bw-fill` fills the clipboard of the machine the shell runs on, so the paste must go to a browser on that same machine. If your browser automation can reach browsers on several machines, select the local one first; otherwise the paste lands nowhere and the field stays empty.
- **Headless Linux shells** (SSH, tmux) often lack `DISPLAY`. `bw-fill` falls back to `DISPLAY=:0` when the local X socket exists.

Verify:

```bash
which bw bwx bw-fill
bwx <H> list folders | jq -r '.[].name'
```

## Folder scope

Resolve the folder ID once and pass it on every item query:

```bash
bwx <H> list folders | jq -r '.[] | select(.name == "<agent-folder>") | .id'
```

Store it as `<F>`.

## Login workflow

Given a target site (e.g. `example.com`):

1. Complete session setup (handle, paste chord, local browser).
2. Navigate to the site's login page.
3. Find the vault item, scoped to the folder:
   ```bash
   bwx <H> list items --folderid <F> --search example.com | jq '.[] | {id, name, username: .login.username}'
   ```
   The `jq` filter keeps the password out of the output.
4. Type `username` into the username field.
5. Focus the password field.
6. Copy the password (prints only `copied`):
   ```bash
   bw-fill <H> <id>
   ```
7. Send `<PASTE>`.
8. Clear the clipboard, whether or not the paste worked (prints only `cleared`):
   ```bash
   bw-fill --clear
   ```
9. Submit the form.

If the field is still empty after the paste, run `bw-fill --clear`, re-check the browser selection, retry once, then hand the login to the user. Two-factor codes are out of scope: the user enters them.

A full worked sequence is in [`../examples/login-flow.md`](../examples/login-flow.md).

## Never

- `bw get password`, or any `bwx` call whose output includes a password field (unfiltered `list items` / `get item` print it). Always filter with `jq` as above.
- An item query without `--folderid <F>`.
- Reading the clipboard back (`pbpaste`, `xclip -o`, `wl-paste`) or screenshotting a revealed password field.
- `bw-fill` before the password field is focused: a paste into the wrong field can expose the password in plain text.
- Leaving the clipboard filled: run `bw-fill --clear` after every paste and whenever the flow stops after `bw-fill` succeeded.
