#!/usr/bin/env bash
# run.sh: run every test suite; exits non-zero if any fails.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
rc=0
for t in tests/test_*.sh; do
    echo "=== $t"
    bash "$t" || rc=1
done
echo "=== tests/test_skill.py"
python3 -m pytest -q tests/test_skill.py || rc=1
exit $rc
