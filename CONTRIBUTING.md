# Contributing

Thanks for considering a contribution. This is a small, security-focused toolkit, so the bar is "obviously correct and obviously leak-free."

## Ground rules

- **No code path may print a secret.** stdout, stderr, files, logs, comments — none of them. If you can't show a change keeps the inject-never-print invariant, it won't merge.
- **Keep it minimal.** Two shell shims and an audit script. Resist adding surface area to a secrets tool.
- **Shell style:** `#!/usr/bin/env bash`, `set -euo pipefail`, quote expansions, prefer `[[ ]]`.

## Before you open a PR

```bash
shellcheck bin/* scripts/*.sh install.sh examples/*.sh
bash -n bin/* scripts/*.sh install.sh           # syntax check
scripts/bws-audit.sh                            # should be FAIL=0
```

CI runs the same checks.

## Good first contributions

- **Windows keychain support** in `bin/bws-token` (Credential Manager via PowerShell). macOS + Linux are covered today; Windows is `PRs welcome`.
- **Additional OS keychain backends** behind the same `bws-token <handle>` interface.
- **Audit coverage** — new leak patterns worth scanning for.

## What won't be accepted

- Anything that stores a token in a file or env var outside the OS keychain.
- A convenience flag that prints a secret value "just for debugging."
- Vendoring or auto-downloading the `bws` binary without checksum verification.
