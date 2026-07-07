---
name: bws-secrets
description: "Teach an agent the secure BWS workflow — inject secrets into subprocesses via `bws run`, never print them to stdout. Covers manifest lookup, the bwsx wrapper, and the security rules."
disable-model-invocation: false
allowed-tools:
  - Bash
  - Read
---

# BWS Secret Injection

Securely hand secrets stored in Bitwarden Secrets Manager (BWS) to commands an agent runs — database credentials, API keys, deploy tokens, anything. Secrets are **injected as environment variables into a child process** via `bws run`; they never pass through stdout, and therefore never enter the agent's context, transcript, or any synced memory.

## The one rule

When an agent runs a command, everything that command prints to stdout becomes part of the model's context — and may be captured in transcripts, logs, or synced notes. So **secrets must be injected, never printed.** `bws run` injects; `bws secret get` prints. Use the former, never the latter in an agent path.

## Prerequisites

Two helpers must be on PATH (installed via this toolkit's `install.sh`):

- **`bws-token <handle>`** — retrieves a machine-account access token from the OS keychain by handle (e.g. `mac`).
- **`bwsx <handle> <bws args...>`** — looks up the token via `bws-token`, exports it for one `exec`, and forwards to `bws`. Keeps the raw token out of argv and shell history.

Verify:

```bash
which bws bws-token bwsx
```

## Manifest discovery

A project that uses BWS keeps a `secrets-manifest.yaml` at its root. It maps logical names to a BWS project UUID and the env-var name the secret becomes — **no credentials**, only routing.

```yaml
injections:
  app-db-prod:
    project: prod          # key into the projects: block below
    env: APP_DB_DSN        # env var that `bws run` injects
  stripe-prod:
    project: prod
    env: STRIPE_API_KEY
  app-db-dev:
    project: nonprod
    env: APP_DB_DSN

projects:
  prod:    "<bitwarden-project-uuid>"
  nonprod: "<bitwarden-project-uuid>"
```

To resolve a logical name to an invocation:

1. Read `secrets-manifest.yaml` at the project root.
2. Find the name under `injections:` → get its `project` and `env`.
3. Find that project under `projects:` → get the UUID.
4. Pass the UUID to `bwsx` (below). The consuming command reads the `env` var.

## Invocation pattern

```bash
bwsx <handle> run --project-id "<uuid>" -- <command-or-script>
```

| Parameter | Value |
|-----------|-------|
| `<handle>` | Machine-account name (e.g. `mac`) — `bwsx` resolves its token via `bws-token` |
| `<uuid>` | BWS project UUID from the manifest `projects:` map |
| `<command>` | Receives **all** of that project's secrets as environment variables |

**Example** — run a script with the `prod` project's secrets injected:

```bash
bwsx mac run --project-id "<prod-uuid>" -- ./deploy.sh
# deploy.sh reads $APP_DB_DSN / $STRIPE_API_KEY from its environment.
```

`bws run` injects **every** secret in the named project (secret name → env var name). You do not filter at inject time — the command simply reads the env var(s) it needs. Want only one secret available? Put it in its own project.

## CRITICAL: security rules

- **NEVER `bws secret get`** in an agent or command path — it writes the value to stdout, which becomes agent context.
- **ALWAYS inject via `bwsx`/`bws run`** — the only approved path.
- **NEVER echo, print, or log a secret value** to stdout, stderr, a file, or a comment.
- **Scripts MUST start with `set -euo pipefail`** and assert the secret arrived before use:

  ```bash
  set -euo pipefail
  : "${APP_DB_DSN:?APP_DB_DSN was not injected}"
  ```

  Fail loud and early — never run against an empty or wrong value.

## Hardening: `--no-inherit-env`

Pass `--no-inherit-env` to give the child **only** the injected secrets — stripping the parent shell environment, including the token, from the subprocess:

```bash
bwsx mac run --project-id "<uuid>" --no-inherit-env -- /abs/path/to/deploy.sh
```

Note: it also clears `PATH`, so use absolute paths or pass needed vars with `--env KEY=VALUE`.

## Reference

Setup, machine-account provisioning, and design rationale: see `docs/operator-guide.md` and `docs/design.md` in the toolkit repo.
