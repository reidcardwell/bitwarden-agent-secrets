# Security Policy

## Threat model

`bws-agent-secrets` exists to keep secrets out of one specific place: an AI agent's context. When an agent runs a command, the command's stdout is read back into the model and frequently persisted (transcripts, memory files, synced notes). The core invariant is therefore:

> **Secrets are injected into a subprocess's environment via `bws run` and are never printed.**

### What this tool does and does not do

- It **does not store** any secret. It shells out to the official Bitwarden `bws` binary.
- It **does not transmit** anything anywhere. The only network actor is `bws` itself, talking to Bitwarden.
- The machine-account access token lives **only** in the OS keychain. The helpers read it at call time and export it for the lifetime of a single `exec`.

### Invariants the audit enforces

`scripts/bws-audit.sh` checks that:

- the installed helpers are unmodified copies of this repo's `bin/`,
- no `BWS_ACCESS_TOKEN` is assigned in a shell profile,
- no BWS token pattern appears in a tracked file or `.env`,
- the `bws` state file (if present) is `0600`,
- a consumer project's `secrets-manifest.yaml` contains no embedded credentials.

## Rules for users

- **Never** use `bws secret get` in an agent or automated path — it writes the value to stdout.
- **Never** hand-write a token into a file, a shell profile, or `~/.config/bws/state`.
- **Always** assert the injected var (`: "${VAR:?missing}"`) and run scripts with `set -euo pipefail`.
- Install the `bws` binary only from the official signed release: <https://github.com/bitwarden/sdk-sm/releases>.

## Reporting a vulnerability

If you find a way this toolkit could leak a secret — a code path that prints one, an injection that lands a value in argv or a file, or a flaw in the audit's coverage — please open a **private security advisory** on this repository (GitHub → Security → Report a vulnerability) rather than a public issue. I'll respond as promptly as I can.

Please do **not** include any real secret value in a report.
