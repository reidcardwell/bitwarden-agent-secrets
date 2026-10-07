# Operator Guide: Using Bitwarden Secrets Manager with AI Agents

**Purpose:** the "I forgot all the details" reload. How to give a command or agent access to a secret stored in Bitwarden Secrets Manager (BWS), choose the project + secret, and do it without ever leaking plaintext into your agent's context. For the *why*, see [`design.md`](./design.md).

---

## 30-second mental model

```
Bitwarden org
  └─ Project (e.g. prod, stage)            ← access is granted per-project
       └─ Secret (e.g. APP_DB_DSN)         ← name = the ENV VAR it becomes
Machine account (e.g. "laptop")            ← granted read on N projects; has ONE token
  └─ access token                          ← lives ENCRYPTED in the OS keychain
Helpers on PATH (~/.local/bin):
  bws        ← official Bitwarden CLI
  bws-token  ← pulls the token from the OS keychain by handle
  bwsx       ← bws-token + bws, so the raw token never hits your command
```

**The one rule that matters:** secrets are injected as **environment variables into a child process** via `bws run`. They are NEVER printed to stdout, because an agent's stdout becomes its context, which may be transcribed, logged, or synced.

---

## Golden security rules

- ✅ **Use `bwsx <handle> run --project-id <uuid> -- <cmd>`**: the only approved path. Injects secrets as env vars into `<cmd>`.
- ❌ **NEVER `bws secret get`** in a command/agent path: it prints the value to stdout.
- ❌ **NEVER echo/print/log a secret** to stdout, stderr, a file, or a comment.
- ✅ Scripts start with `set -euo pipefail` and assert the var: `: "${APP_DB_DSN:?missing}"`.
- ✅ The token lives only in the OS keychain. Never in `.env`, a shell profile, a tracked/synced file, or `~/.config/bws/state` (that path is bws's own *encrypted* store; never hand-write a token there).

---

## How to give a command access to BWS

There is no per-command permission system. Any process on the machine can read whatever the machine-account token is granted (the BW project grants are the ceiling). "Giving a command access" = **write the command to invoke `bwsx` and read the injected env var.**

### The pattern

```bash
bwsx <handle> run --project-id "<PROJECT-UUID>" -- <your-command-or-script>
```

- `<handle>`: the machine-account handle (`bwsx` fetches its token from the keychain).
- `--project-id <uuid>`: **which project.** Get UUIDs from your `secrets-manifest.yaml` `projects:` map or `bws project list`.
- `<command>`: receives **all** of that project's secrets as environment variables.

### Which secret? Default is ALL, selection is by env-var name

`bws run` injects **every secret in the chosen project** as an env var (secret *name* → env var name). You don't filter at inject time; your command reads the env var(s) it wants:

```bash
bwsx <handle> run --project-id "<uuid>" -- sh -c '
  set -euo pipefail
  : "${APP_DB_DSN:?not injected}"
  some-tool "$APP_DB_DSN"   # uses the secret, never prints it
'
```

Want just one secret available? Put it in its own project. There is no `bws run --only-secret X` filter: injection granularity is the *project*; secret selection is *which env var your code reads*.

### Tier-agnostic trick (dev vs stage from one script)

If two projects (e.g. `prod` and `stage`) both hold a secret named `APP_DB_DSN`, the **same script** runs against either tier; only the project changes:

```bash
bwsx <handle> run --project-id "<prod-uuid>"  -- ./sync.sh   # $APP_DB_DSN = prod value
bwsx <handle> run --project-id "<stage-uuid>" -- ./sync.sh   # $APP_DB_DSN = stage value
```

### Hardening (optional)

```bash
bwsx <handle> run --no-inherit-env --project-id "<uuid>" -- /abs/path/sync.sh
```

`--no-inherit-env` gives the child ONLY the injected secrets (not your shell env, including the token). It also strips `PATH`, so use absolute paths or pass needed vars with `--env KEY=VALUE`.

---

## Copy-paste recipes

```bash
# List projects a handle can reach (names + UUIDs, no secret values; safe):
BWS_ACCESS_TOKEN=$(bws-token <handle>) bws project list

# List a project's secret NAMES only (values stripped in-pipe; safe):
BWS_ACCESS_TOKEN=$(bws-token <handle>) \
  bws secret list "<PROJECT-UUID>" --output json \
  | python3 -c 'import json,sys;[print("  -",s["key"]) for s in json.load(sys.stdin)]'

# Run a script with a project's secrets injected (the normal use):
bwsx <handle> run --project-id "<PROJECT-UUID>" -- ./your-script.sh

# Inspect ONE secret's value: HUMAN, OWN TERMINAL ONLY (prints plaintext!):
bwsx <handle> secret get "<SECRET-ID>"
```

---

## Adding things later

**Add a secret to a project** (BW web UI → Secrets Manager → Secrets):
- Name it `UPPER_SNAKE_CASE` (it becomes the env var). Convention: `<APP>_<PURPOSE>` (e.g. `APP_DB_DSN`, `STRIPE_API_KEY`).
- Use the **same name across tiers** (prod/stage) so scripts stay tier-agnostic.
- Store the whole value (e.g. a full DSN, host included). Put prose in the secret's *note* field.

**Grant a machine account a new project** (BW web UI → Machine accounts → `<handle>` → **Projects** tab → add, **Read**). The control is under the machine account's Projects tab.

**Tell agents about a new connection**: add it to that project's `secrets-manifest.yaml`:
```yaml
injections:
  <logical-name>: { project: <key>, env: <ENV_VAR_NAME> }
projects:
  <key>: "<project-uuid>"
```
> The token reaching a project ≠ agents knowing about it. The skill resolves connections from the **manifest**, not live BWS. A project is invisible to the workflow until it has a manifest entry.

**Set up a NEW machine:**
1. Install the official `bws` binary to `~/.local/bin` (see [`install-bws.md`](./install-bws.md)).
2. Create a per-machine BW machine account (e.g. `linux-dev`), grant it the projects it needs, mint a token.
3. Store the token in the OS keychain, never a file:
   - macOS: `security add-generic-password -a "$USER" -s bws-<machine> -w` (trailing `-w` prompts, no echo; `-U` to update).
   - Linux desktop: `secret-tool store --label='bws <machine>' service bws-<machine>`.
   - Linux headless: `pass insert bws-<machine>`.
4. Deploy helpers: run this repo's `./install.sh`.
5. Verify: `bwsx <machine> run --project-id "<uuid>" -- printenv SOMEVAR | wc -c` (length only, no value), then `skills/bitwarden/scripts/bws-audit.sh`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `bws project list` returns `[]` | Token valid but the machine account has **no project grants** → grant it a project. |
| `command not found: bws` (just installed) | Shell cached the miss → `rehash` (zsh) or open a new tab. Or `~/.local/bin` not on PATH. |
| `security: ... could not be found` | No keychain entry for that handle → run the `add-generic-password` step. |
| Skill not found by the agent | The skill wasn't installed → re-run `./install.sh` (answer yes), or copy `skills/bitwarden/` into your agent's skills dir. |
| Secret injected but script sees empty var | Wrong `--project-id`, the secret isn't in that project, or its name ≠ the var you read. |
