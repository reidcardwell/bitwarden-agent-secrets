#!/usr/bin/env bash
# Minimal injected-script example. Run via:
#   bwsx mac run --project-id "<uuid>" -- ./sync.sh
set -euo pipefail
: "${APP_DB_DSN:?APP_DB_DSN was not injected}"
echo "Secret injected (length ${#APP_DB_DSN}) — value never printed."
