#!/usr/bin/env bash
# sync.sh — worked example: a DB sync that reads its credential from the
# environment (injected by `bws run`) and NEVER prints it.
#
# Run it injected, never directly:
#   bwsx <handle> run --project-id "<prod-uuid>" -- ./sync.sh
#   bwsx <handle> run --project-id "<stage-uuid>" -- ./sync.sh   # same script, other tier

set -euo pipefail

# Assert the secret was injected. Fail loud and early if not.
: "${APP_DB_DSN:?APP_DB_DSN was not injected — run this via 'bwsx <handle> run --project-id <uuid> --'}"

# Use the DSN. It is read from the environment and never echoed, logged, or
# placed on the command line (which would expose it via 'ps' and shell history).
#
# Example (mysql): never pass the password as -p<value>; let the client read the
# DSN/URL or use a defaults-extra-file / MYSQL_PWD so it stays out of argv.
#
#   mysql --defaults-extra-file=<(printf '[client]\n...') -e 'SELECT 1'
#
# Placeholder action — replace with your real sync:
echo "Connecting (DSN length: ${#APP_DB_DSN} chars) — value never printed."
echo "... running sync ..."
echo "Done."
