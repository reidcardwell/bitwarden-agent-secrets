# Design & Rationale

Why this toolkit exists and why it's shaped the way it is.

## The threat model AI agents introduce

A secrets manager solves *storage*: credentials live encrypted, access is scoped, rotation is centralized. That problem was solved long ago.

AI agents introduce a *new* boundary that storage doesn't address: the boundary between **a subprocess's environment** and **the model's context**.

When an agent runs a command, everything that command writes to stdout/stderr is read back by the model and becomes part of the conversation. That conversation is frequently:

- written to a session transcript on disk,
- summarized into "memory" files,
- and, increasingly, synced to cloud notes or knowledge bases.

So the naive approach to giving an agent a credential:

```bash
SECRET=$(bws secret get MY_SECRET)   # prints the value to stdout
```

This quietly turns the agent's own memory pipeline into an exfiltration path. The credential, which should have existed for milliseconds inside one process, comes to rest in every place the transcript travels. No attacker required; you built the leak yourself.

## The principle: inject, never print

The fix is to never let the secret cross into the agent's context in the first place. Secrets belong in the **environment variables of the child process that needs them**, and nowhere else:

- **Not stdout**: the agent reads it.
- **Not the command line**: it appears in `ps` and shell history.
- **Not a file** the agent or a sync daemon can read.

Bitwarden's CLI provides the right primitive: `bws run` fetches a project's secrets, injects them as environment variables into a named subprocess, and prints nothing. The value materializes inside that process, is used, and evaporates on exit.

```bash
bws run --project-id "<uuid>" -- ./script.sh   # script reads $SECRET from env
```

That single inversion, from "fetch then pass" to "inject into the child", is the entire security story. The rest of this toolkit is ergonomics and guardrails around it.

## Design decisions

**Token in the OS keychain, never a file.** The machine-account access token is the master key; it lives only in the OS keychain (macOS `security`, Linux `secret-tool`/`pass`). One token per *machine*. `bws-token` is the single per-OS lookup point, so the rest of the toolkit is OS-agnostic.

**A wrapper keeps the token out of argv.** `bwsx <handle> <args...>` reads the token from the keychain, exports it for one `exec`, and hands off to `bws`. The token is never an argument and never lands in history.

**Projects are environment tiers; secret names are env-var names.** Storing the same secret name across `prod`/`stage` projects lets one tier-agnostic script target any tier by swapping a project UUID. Names map 1:1 to env vars, so the manifest and the code stay in sync by construction.

**A committed, secret-free manifest is the agent's map.** `secrets-manifest.yaml` routes logical names → project UUID + env-var name, with no credentials. The agent learns *what to inject and where* from version control, not by querying the secrets backend at runtime. A token *reaching* a project is not the same as the agent *knowing* it exists.

**Password Manager logins go through a clipboard bridge.** A browser form can't read an environment variable, so `bw-fill` pipes `bw get password` straight into the clipboard tool and prints only `copied`; the agent pastes into the focused field and runs `bw-fill --clear` at once. Item lookups are scoped to one vault folder and filtered with `jq` so the password field never reaches stdout. This is a weaker guarantee than injection: the clipboard is readable by other apps, history managers and sync for as long as it holds the value. Clearing immediately narrows that window; prefer Secrets Manager whenever the consumer can take an env var.

**An audit script enforces the invariants.** `bws-audit.sh` verifies the helpers are installed and unmodified, scans for tokens leaked into profiles/`.env`/tracked files, checks the keychain-only rule, and confirms the manifest is credential-free. It's a pre-flight a human or an agent can run before trusting the setup.

## Why the official binary

`bws` is installed as the **official release binary** from <https://github.com/bitwarden/sdk-sm/releases>, not via `cargo` or a third-party tap. For a tool whose entire job is handling secrets, the provenance of the binary is part of the threat model; the vendor's signed release is the trustworthy source.

## Non-goals

- **Not a secrets store.** This wraps Bitwarden Secrets Manager; it stores nothing itself and transmits nothing anywhere except by shelling out to the official `bws`.
- **Not a Laravel/runtime-config tool.** The use case is agents and CLIs running data tasks from a workstation outward, not the request lifecycle of a long-running app (where `env()`/config-cache rules would apply instead).
- **Not per-secret injection filtering.** Injection granularity is the project; selection is which env var your code reads.
