---
name: bitwarden
description: "Hand Bitwarden secrets to the commands an agent runs without the value ever entering the agent's context. Secrets Manager: inject into a child process with `bws run` via `bwsx`. Password Manager: deliver a login password through the clipboard with `bw-fill`. Use for database credentials, API keys, deploy tokens, and browser logins."
disable-model-invocation: false
allowed-tools:
  - Bash
  - Read
---

# Bitwarden Agent Secrets

Everything a command prints to stdout becomes part of the agent's context, and from there it can land in transcripts, logs, memory files and synced notes. So a secret must reach the thing that needs it **without being printed**. This skill covers both Bitwarden products:

| Need | Product | Delivery | Read |
|------|---------|----------|------|
| A script or CLI needs a credential (DSN, API key, token) | Secrets Manager (`bws`) | Injected as an env var into the child process | [`references/secrets-manager.md`](references/secrets-manager.md) |
| A browser login form needs a password | Password Manager (`bw`) | Copied to the clipboard, pasted, then cleared | [`references/password-manager.md`](references/password-manager.md) |

Read only the reference for the task at hand.

## Rules for both products

- **Inject or bridge, never print.** Never run a command whose output is a secret value: no `bws secret get`, no `bw get password`, no `echo "$SECRET"`.
- **Never echo, log, or write a secret** to stdout, stderr, a file, a comment, or a diagnostic message.
- **Never read a secret back to check it.** No reading the clipboard, no printing an env var, no screenshot of a revealed field. Check length only (`${#VAR}`) if you must.
- **Always go through the wrappers** (`bwsx`, `bwx`, `bw-fill`). They pull credentials from the OS secret store at call time, so nothing lands in argv or shell history.
- **Stop on failure.** If a wrapper exits non-zero, report the error text and stop. Never work around it by fetching the secret another way.

## Install

The `scripts/` directory holds the wrappers. They must be on `PATH`:

```bash
install -m 0755 scripts/{bwsx,bws-token,bwx,bw-token,bw-unlock,bw-fill} ~/.local/bin/
```

The toolkit repo's `install.sh` does the same. Each wrapper is a standalone file with no shared dependencies.

| Wrapper | Product | Role |
|---------|---------|------|
| `bws-token <handle>` | Secrets Manager | Reads the machine-account token for `<handle>` from the OS secret store |
| `bwsx <handle> <bws args...>` | Secrets Manager | Exports that token for one `exec` of `bws` |
| `bw-token <handle> <clientid\|clientsecret\|master>` | Password Manager | Reads one API or unlock credential from the OS secret store |
| `bw-unlock <handle>` | Password Manager | Logs in with the API key and prints a session key (for the other wrappers, never for you) |
| `bwx <handle> <bw args...>` | Password Manager | Runs `bw` with a fresh session |
| `bw-fill <handle> <item-id>` / `bw-fill --clear` | Password Manager | Copies an item's password to the clipboard / empties it |
| `bws-audit.sh` | Both | Audit: install state, leaked tokens, manifest hygiene. Run by path, not installed |

**Secret store lookup.** `bws-token` and `bw-token` try macOS Keychain (`security`), then `secret-tool` (Linux desktop), then `pass` (Linux headless). Entries are named `bws-<handle>` and `bw-{clientid,clientsecret,master}-<handle>`. A `<handle>` is just the label you chose when storing them, typically one per machine. The Secrets Manager handle and the Password Manager handle on the same machine may differ.

## Audit

```bash
scripts/bws-audit.sh [--manifest <file>] [<project-dir>]
```

Checks that the installed wrappers match `scripts/`, that no token sits in a shell profile, `.env` or tracked file, and that the project's manifest is credential-free. `--manifest` defaults to `secrets-manifest.yaml`; a relative path resolves against `<project-dir>`. Exit 0 means no FAIL lines.
