# bitwarden-agent-secrets

**Inject, never print.** Hand secrets from [Bitwarden](https://bitwarden.com/) to the commands your AI agent runs, without the secret ever entering the agent's context. Covers both Bitwarden products: **Secrets Manager** for credentials a script needs, and **Password Manager** for browser logins.

---

## The problem

Most projects keep credentials in a plaintext `.env` file. Two things go wrong with that. First, plaintext at rest is a standing liability: one `cat`, one backup, one loose file permission from leaking. Second, the moment you work from more than one machine, that `.env` gets copied around and drifts: there's no source of truth, just stale copies.

A secrets manager fixes both: one encrypted vault as the source of truth, per-machine access you can revoke independently, and nothing plaintext on disk.

**AI agents add a third problem the secrets manager doesn't solve.** When an agent runs a command, everything that command prints to stdout becomes part of the model's context, and that context is often written to a transcript, summarized into a memory file, and synced to the cloud. So the obvious way to give an agent a credential:

```bash
SECRET=$(bws secret get MY_SECRET)   # prints the value → agent reads it → it's now in your transcript
```

This quietly turns your agent's own memory pipeline into an exfiltration path. You didn't get breached; you built the leak yourself. **This toolkit is the part that closes that gap.**

## The fix

**Secrets Manager: inject into the child process.** `bws run` puts the secret in the environment of the one process that needs it. It never crosses into the agent's context:

```bash
bwsx <handle> run --project-id "<uuid>" -- ./sync.sh
# sync.sh reads $APP_DB_DSN from its environment. The agent never sees the value.
```

**Password Manager: the clipboard bridge.** A browser login form can't read an env var, so `bw-fill` pipes the password from `bw` straight into the clipboard, the agent pastes it into the focused field, and `bw-fill --clear` empties the clipboard at once. The agent only ever sees `copied` and `cleared`.

### The two paths are not equally safe

Environment injection exposes the secret to one child process for its lifetime. The clipboard is readable by **any** app on the machine, by clipboard history managers, and by clipboard sync (Universal Clipboard, KDE Connect) for as long as it holds the password. Clearing immediately shortens that window; it cannot close it. Use the clipboard path only on a machine you control, with clipboard history and sync turned off, and prefer Secrets Manager wherever the consumer can read an env var.

## What's in the box

Everything ships in one self-contained folder, [`skills/bitwarden/`](./skills/bitwarden/):

| Piece | What it does |
|-------|--------------|
| `SKILL.md` | A [Claude Code](https://docs.claude.com/en/docs/claude-code) skill: shared rules, install, and which reference to read |
| `references/secrets-manager.md` | The injection workflow: manifest lookup, `bwsx`, script rules |
| `references/password-manager.md` | The browser-login workflow: folder scoping, `bw-fill`, clearing |
| `scripts/bws-token`, `scripts/bwsx` | Secrets Manager: read the machine-account token from the OS secret store, run `bws` with it |
| `scripts/bw-token`, `scripts/bw-unlock`, `scripts/bwx`, `scripts/bw-fill` | Password Manager: read API and unlock credentials, run `bw` with a fresh session, copy or clear a password on the clipboard |
| `scripts/bws-audit.sh` | Audit: verifies the install, scans for leaked tokens, checks the manifest |
| `examples/` | A worked `sync.sh`, a `secrets-manifest.yaml`, and a browser login walkthrough |

Also: [`install.sh`](./install.sh), [`docs/`](./docs/) (operator guide, design rationale, installing `bws`), and [`tests/`](./tests/).

## Quickstart

```bash
# 1. Install the official CLIs you need:
#    Secrets Manager: bws (see docs/install-bws.md)
#    Password Manager: bw  (https://bitwarden.com/help/cli/)

# 2. Store credentials in the OS secret store, never a file. <handle> is any label, e.g. one per machine.
#    Secrets Manager machine-account token:
#      macOS:          security add-generic-password -a "$USER" -s bws-<handle> -w
#      Linux desktop:  secret-tool store --label='bws <handle>' service bws-<handle>
#      Linux headless: pass insert bws-<handle>
#    Password Manager: the same, for bw-clientid-<handle>, bw-clientsecret-<handle>, bw-master-<handle>

# 3. Install the wrappers (and optionally the Claude Code skill):
./install.sh

# 4. Secrets Manager: add a secrets-manifest.yaml to your project (see examples/), then:
bwsx <handle> run --project-id "<uuid>" -- ./your-script.sh

# 5. Audit anytime:
skills/bitwarden/scripts/bws-audit.sh [--manifest <file>] [<project-dir>]
```

## The golden rules

- ✅ **Inject** via `bwsx ... run --project-id <uuid> -- <cmd>`, or **bridge** via `bw-fill` + `bw-fill --clear`.
- ❌ **Never** `bws secret get` or `bw get password` in an agent path: they print to stdout.
- ❌ **Never** `bw list items` without filtering out the password field (`| jq '.[] | {id, name, username: .login.username}'`).
- ❌ **Never** echo, log, or write a secret value anywhere, or read the clipboard back.
- ✅ Credentials live **only** in the OS secret store, never a file, profile, or the bws state file.
- ✅ Scripts start with `set -euo pipefail` and assert the var: `: "${MY_SECRET:?missing}"`.

Full rationale in [`docs/design.md`](./docs/design.md). Day-to-day Secrets Manager reference in [`docs/operator-guide.md`](./docs/operator-guide.md).

## Releases and vendoring

Releases are tagged `vYYYY.MM.DD` (`.N` for a second release the same day). To embed the skill in another repo, copy `skills/bitwarden/` from a tag, record the tag and commit, and treat the copy as read-only: change it here and re-copy.

## Upgrading from `bws-agent-secrets`

This repo was `bws-agent-secrets`, Secrets Manager only; GitHub redirects the old URL. The skill is now `bitwarden` (was `bws-secrets`), the wrappers moved from `bin/` into `skills/bitwarden/scripts/`, and the audit moved with them. Re-run `./install.sh` and delete any old `~/.claude/skills/bws-secrets/`.

## Works with

First-class with **Claude Code** (the `skills/bitwarden/` skill drops into `~/.claude/skills/`). The pattern itself is runtime-agnostic: any agent that runs subprocesses can use the wrappers; the skill markdown is just how Claude Code learns the workflow.

## Security

This toolkit stores nothing and transmits nothing; it shells out to the official `bws` and `bw` binaries only. See [`SECURITY.md`](./SECURITY.md) for the threat model and disclosure policy.

## License

[MIT](./LICENSE) © 2026 Reid Cardwell
