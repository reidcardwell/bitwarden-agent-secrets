# Security Policy

## Threat model

`bitwarden-agent-secrets` exists to keep secrets out of one specific place: an AI agent's context. When an agent runs a command, the command's stdout is read back into the model and frequently persisted (transcripts, memory files, synced notes). The core invariant is therefore:

> **Secrets are injected into a subprocess's environment via `bws run`, or bridged through the clipboard via `bw-fill`, and are never printed.**

### What this tool does and does not do

- It **does not store** any secret. It shells out to the official Bitwarden `bws` and `bw` binaries.
- It **does not transmit** anything anywhere. The only network actors are `bws` and `bw`, talking to Bitwarden.
- Credentials (the Secrets Manager machine-account token, the Password Manager API key and master password) live **only** in the OS secret store. The wrappers read them at call time and export them for the lifetime of a single `exec`.

### The clipboard path is weaker

`bw-fill` keeps a password out of the agent's context, but while it sits on the clipboard any app on the machine, a clipboard history manager, or clipboard sync can read it. `bw-fill --clear` shortens that window and cannot close it. This is an accepted, documented limit, not a vulnerability; use the clipboard path only on a machine you control with clipboard history and sync off.

### Invariants the audit enforces

`skills/bitwarden/scripts/bws-audit.sh` checks that:

- the installed wrappers are unmodified copies of `skills/bitwarden/scripts/`,
- no `BWS_ACCESS_TOKEN`, `BW_SESSION`, `BW_CLIENTSECRET`, `BW_PASSWORD` or `BW_MASTER` is assigned in a shell profile,
- no BWS token pattern appears in a tracked file or `.env`,
- the `bws` state file (if present) is `0600`,
- a consumer project's manifest (`secrets-manifest.yaml`, or the file named by `--manifest`) contains no embedded credentials.

## Rules for users

- **Never** use `bws secret get` or `bw get password` in an agent or automated path: they write the value to stdout.
- **Never** run `bw list items` / `bw get item` without filtering out the password field.
- **Never** read the clipboard back to check a paste.
- **Never** hand-write a token into a file, a shell profile, or `~/.config/bws/state`.
- **Always** assert the injected var (`: "${VAR:?missing}"`) and run scripts with `set -euo pipefail`.
- Install `bws` only from the official signed release (<https://github.com/bitwarden/sdk-sm/releases>) and `bw` only from Bitwarden's official distribution.

## Reporting a vulnerability

If you find a way this toolkit could leak a secret — a code path that prints one, an injection that lands a value in argv or a file, or a flaw in the audit's coverage — please open a **private security advisory** on this repository (GitHub → Security → Report a vulnerability) rather than a public issue. I'll respond as promptly as I can.

Please do **not** include any real secret value in a report.
