# Contributing

Thanks for considering a contribution. This is a small, security-focused toolkit, so the bar is "obviously correct and obviously leak-free."

## Ground rules

- **No code path may print a secret.** stdout, stderr, files, logs, comments — none of them. If you can't show a change keeps the inject-never-print invariant, it won't merge.
- **Keep it minimal.** Six standalone shell wrappers and an audit script. Resist adding surface area to a secrets tool.
- **Everything shipped lives in `skills/bitwarden/`.** Tests live in `tests/` and must never reach a real secret store (see `tests/test_bws_scripts.sh` for the isolation pattern).
- **Shell style:** `#!/usr/bin/env bash`, `set -euo pipefail`, quote expansions, prefer `[[ ]]`.

## Before you open a PR

```bash
shellcheck skills/bitwarden/scripts/* skills/bitwarden/examples/*.sh install.sh tests/*.sh
tests/run.sh                                     # all suites (needs pytest)
skills/bitwarden/scripts/bws-audit.sh            # should be FAIL=0 after install
```

CI runs the same checks.

## Good first contributions

- **Windows keychain support** in `bws-token` / `bw-token` (Credential Manager via PowerShell). macOS + Linux are covered today; Windows is `PRs welcome`.
- **Additional OS keychain backends** behind the same `bws-token <handle>` interface.
- **Audit coverage** — new leak patterns worth scanning for.

## What won't be accepted

- Anything that stores a token in a file or env var outside the OS keychain.
- A convenience flag that prints a secret value "just for debugging."
- Vendoring or auto-downloading the `bws` binary without checksum verification.
