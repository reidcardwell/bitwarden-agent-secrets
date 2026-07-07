# bws-agent-secrets

**Inject, never print.** Safely hand secrets from [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/) to commands your AI agent runs, without the secret ever entering the agent's context.

---

## The problem

Most projects keep credentials in a plaintext `.env` file. Two things go wrong with that. First, plaintext at rest is a standing liability: one `cat`, one backup, one loose file permission from leaking. Second, the moment you work from more than one machine, that `.env` gets copied around and drifts: there's no source of truth, just stale copies.

A secrets manager like Bitwarden Secrets Manager fixes both: one encrypted vault as the source of truth, per-machine access tokens you can revoke independently, and nothing plaintext on disk. That's the baseline win, and you get it the moment you adopt the tool.

**AI agents add a third problem the secrets manager doesn't solve.** When an agent runs a command, everything that command prints to stdout becomes part of the model's context, and that context is often written to a transcript, summarized into a memory file, and synced to the cloud. So the obvious way to give an agent a credential:

```bash
SECRET=$(bws secret get MY_SECRET)   # prints the value → agent reads it → it's now in your transcript
```

This quietly turns your agent's own memory pipeline into an exfiltration path. You didn't get breached; you built the leak yourself. **This toolkit is the part that closes that gap.**

## The fix

Inject the secret as an **environment variable into the child process** that needs it, via `bws run`. It never crosses into the agent's context:

```bash
bwsx mac run --project-id "<uuid>" -- ./sync.sh
# sync.sh reads $MY_SECRET from its environment. The agent never sees the value.
```

That single inversion, from *fetch-then-pass* to *inject-into-the-child*, is the whole idea. This toolkit is the ergonomics and guardrails around it.

## What's in the box

| Piece | What it does |
|-------|--------------|
| `bin/bws-token` | Pulls a machine-account token from the OS keychain by handle (macOS / Linux). |
| `bin/bwsx` | Wraps `bws-token` + `bws` so the raw token never appears in argv or history. |
| `skills/bws-secrets/` | A [Claude Code](https://docs.claude.com/en/docs/claude-code) skill teaching an agent the secure workflow. |
| `scripts/bws-audit.sh` | Security audit: verifies install, scans for leaked tokens, checks the manifest. |
| `examples/` | A worked `sync.sh` + `secrets-manifest.yaml`. |
| `docs/` | Operator guide, design rationale, and how to install the official `bws` binary. |

## Quickstart

```bash
# 1. Install the official Bitwarden CLI (see docs/install-bws.md).

# 2. Store your machine-account token in the OS keychain (NEVER a file):
#    macOS:
security add-generic-password -a "$USER" -s bws-mac -w
#    Linux desktop:  secret-tool store --label='bws mac' service bws-mac
#    Linux headless: pass insert bws-mac

# 3. Install the helpers (and optionally the Claude Code skill):
./install.sh

# 4. Add a secrets-manifest.yaml to your project (see examples/), then run:
bwsx mac run --project-id "<uuid>" -- ./your-script.sh

# 5. Audit anytime:
scripts/bws-audit.sh
```

## The golden rules

- ✅ **Inject** via `bwsx ... run --project-id <uuid> -- <cmd>`: the only approved path.
- ❌ **Never** `bws secret get` in an agent path: it prints to stdout.
- ❌ **Never** echo, log, or write a secret value anywhere.
- ✅ Token lives **only** in the OS keychain, never a file, profile, or the bws state file.
- ✅ Scripts start with `set -euo pipefail` and assert the var: `: "${MY_SECRET:?missing}"`.

Full rationale in [`docs/design.md`](./docs/design.md). Day-to-day reference in [`docs/operator-guide.md`](./docs/operator-guide.md).

## Works with

First-class with **Claude Code** (the `skills/bws-secrets/` skill drops into `~/.claude/skills/`). The pattern itself is runtime-agnostic: any agent that runs subprocesses can use `bwsx`; the skill markdown is just how Claude Code learns the workflow. For another runtime, point your agent at [`docs/operator-guide.md`](./docs/operator-guide.md).

## Security

This toolkit stores nothing and transmits nothing; it shells out to the official `bws` binary only. See [`SECURITY.md`](./SECURITY.md) for the threat model and disclosure policy.

## License

[MIT](./LICENSE) © 2026 Reid Cardwell
