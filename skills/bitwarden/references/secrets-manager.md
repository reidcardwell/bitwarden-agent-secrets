# Secrets Manager: inject into the child process

Hand a credential to a script or CLI as an environment variable of that one child process. `bws run` injects; `bws secret get` prints. Use the former, never the latter.

## Prerequisites

- The official `bws` binary on `PATH` (<https://github.com/bitwarden/sdk-sm/releases>).
- `bws-token` and `bwsx` on `PATH`.
- A machine-account access token stored in the OS secret store as `bws-<handle>`:
  - macOS: `security add-generic-password -a "$USER" -s bws-<handle> -w`
  - Linux desktop: `secret-tool store --label='bws <handle>' service bws-<handle>`
  - Linux headless: `pass insert bws-<handle>`

Verify (prints secret **names and IDs**, never values):

```bash
which bws bws-token bwsx
bwsx <handle> project list
```

## Manifest

A project that consumes secrets keeps a committable, credential-free manifest at its root. The toolkit's convention is `secrets-manifest.yaml`; some projects use another name (pass it to the audit with `--manifest`). It maps logical names to a Bitwarden project UUID and the env var each secret becomes:

```yaml
injections:
  app-db-prod:
    project: prod          # key into the projects: block below
    env: APP_DB_DSN        # env var that `bws run` injects
  stripe-prod:
    project: prod
    env: STRIPE_API_KEY

projects:
  prod:    "<bitwarden-project-uuid>"
  nonprod: "<bitwarden-project-uuid>"
```

To resolve a logical name:

1. Read the manifest at the project root.
2. Find the name under its connections or injections block: get `project` and `env`.
3. Find that project under `projects:`: get the UUID.
4. Pass the UUID to `bwsx`. The command reads the `env` var.

## Invocation

```bash
bwsx <handle> run --project-id "<uuid>" -- <command-or-script>
```

`bws run` injects **every** secret in the project (secret name becomes the env var name). The command reads the ones it needs. To expose only one secret, give it its own project.

Example (`examples/sync.sh`):

```bash
bwsx <handle> run --project-id "<prod-uuid>" -- ./sync.sh
```

## Script requirements

Scripts that receive secrets start with `set -euo pipefail` and assert the variable arrived before using it, so a missing injection fails loudly instead of running against an empty value:

```bash
set -euo pipefail
: "${APP_DB_DSN:?APP_DB_DSN was not injected}"
```

Never put the value on a command line (visible in `ps` and shell history). Let the client read it from the environment or a temporary defaults file.

## Hardening: `--no-inherit-env`

Give the child **only** the injected secrets, stripping the parent environment (including the token):

```bash
bwsx <handle> run --project-id "<uuid>" --no-inherit-env -- /abs/path/to/sync.sh
```

This also clears `PATH`, so use absolute paths or pass needed variables with `--env KEY=VALUE`.

## Never

- `bws secret get` in an agent or automated path: it prints the value.
- `BWS_ACCESS_TOKEN=...` in a shell profile, `.env`, or tracked file: the token lives only in the OS secret store.
