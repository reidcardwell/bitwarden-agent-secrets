#!/usr/bin/env bash
# test_bws_scripts.sh: unit tests for bws-token and bwsx
#
# Usage: bash tests/test_bws_scripts.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/bitwarden" && pwd)"
BWS_TOKEN_SCRIPT="$SCRIPT_DIR/scripts/bws-token"
BWSX_SCRIPT="$SCRIPT_DIR/scripts/bwsx"

PASS=0
FAIL=0

# ============================================================================
# Output Helpers
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[PASS]${NC}  $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; FAIL=$((FAIL + 1)); }
header() { echo ""; echo -e "${BLUE}--- $* ---${NC}"; }

assert_equals() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        ok "$label"
    else
        fail "$label — expected: $(printf '%q' "$expected"), got: $(printf '%q' "$actual")"
    fi
}

assert_exit_code() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" -eq "$expected" ]]; then
        ok "$label (exit $expected)"
    else
        fail "$label — expected exit $expected, got $actual"
    fi
}

# ============================================================================
# Setup: Temp directory and mock executables
# ============================================================================

TMPDIR_BASE="$(mktemp -d)"
mkdir -p "$TMPDIR_BASE"

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

SECURITY_TOKEN="mock-security-token"
SECRET_TOOL_TOKEN="mock-secretool-token"
PASS_TOKEN="mock-pass-token"
BWS_TOKEN_VALUE="mock-bws-access-token"

# Helper: write and chmod a mock script
write_mock() {
    local path="$1" body="$2"
    printf '#!/bin/bash\n%s\n' "$body" > "$path"
    chmod +x "$path"
}

# Create mock directories for each PATH scenario
DIR_ALL="$TMPDIR_BASE/all"              # security + secret-tool + pass
DIR_NO_SEC="$TMPDIR_BASE/no-sec"        # secret-tool + pass (no security)
DIR_NO_LIBSEC="$TMPDIR_BASE/no-libsec" # pass only
DIR_NONE="$TMPDIR_BASE/none"            # no store commands
DIR_BWS="$TMPDIR_BASE/bws"             # bws + bws-token mocks for bwsx test
DIR_FAIL_SEC="$TMPDIR_BASE/fail-sec"   # security exits non-zero (key not found)
DIR_BWS_EMPTY="$TMPDIR_BASE/bws-empty" # bws-token returns empty string

mkdir -p "$DIR_ALL" "$DIR_NO_SEC" "$DIR_NO_LIBSEC" "$DIR_NONE" "$DIR_BWS" "$DIR_FAIL_SEC" "$DIR_BWS_EMPTY"

# DIR_ALL mocks
write_mock "$DIR_ALL/security"    "echo \"$SECURITY_TOKEN\""
write_mock "$DIR_ALL/secret-tool" "echo \"$SECRET_TOOL_TOKEN\""
write_mock "$DIR_ALL/pass"        "echo \"$PASS_TOKEN\""

# DIR_NO_SEC mocks (no security)
write_mock "$DIR_NO_SEC/secret-tool" "echo \"$SECRET_TOOL_TOKEN\""
write_mock "$DIR_NO_SEC/pass"        "echo \"$PASS_TOKEN\""

# DIR_NO_LIBSEC mocks (pass only)
write_mock "$DIR_NO_LIBSEC/pass" "echo \"$PASS_TOKEN\""

# DIR_BWS mocks (for bwsx)
write_mock "$DIR_BWS/bws-token" "echo \"$BWS_TOKEN_VALUE\""
# shellcheck disable=SC2016  # expands inside the mock, not here
write_mock "$DIR_BWS/bws"       'echo "BWS_ACCESS_TOKEN=$BWS_ACCESS_TOKEN"; echo "args: $*"'

# DIR_FAIL_SEC mocks (security exits 44 = key not found, no other store)
write_mock "$DIR_FAIL_SEC/security" "exit 44"

# DIR_BWS_EMPTY mocks (bws-token echoes nothing, bws is present)
write_mock "$DIR_BWS_EMPTY/bws-token" "echo ''"
write_mock "$DIR_BWS_EMPTY/bws"       'echo "should not be reached"'

# ============================================================================
# Build a "clean base PATH" that strips directories containing real store cmds
# This prevents real system commands (e.g. /usr/bin/security on macOS) from
# leaking into tests that want to control which store is available.
# ============================================================================

# Drop EVERY PATH entry that holds a real store command. Checking only the first
# hit from `command -v` misses aliases such as /bin -> /usr/bin (usrmerge), which
# let the "no store" case reach the real `pass` and print a real token.
BASE_PATH=""
IFS=':' read -ra _path_parts <<< "$PATH"
for _dir in "${_path_parts[@]}"; do
    [[ -z "$_dir" ]] && continue
    for _cmd in security secret-tool pass; do
        [[ -x "$_dir/$_cmd" ]] && continue 2
    done
    BASE_PATH="${BASE_PATH:+${BASE_PATH}:}${_dir}"
done
unset _cmd _path_parts _dir

# Stripping /usr/bin also drops bash, which the scripts' `#!/usr/bin/env bash`
# needs. Re-expose bash alone from a private dir.
mkdir -p "$TMPDIR_BASE/toolbin"
ln -s "$(command -v bash)" "$TMPDIR_BASE/toolbin/bash"
BASE_PATH="$TMPDIR_BASE/toolbin${BASE_PATH:+:$BASE_PATH}"

# Defense in depth: even if a real store slipped through, it must find nothing.
export HOME="$TMPDIR_BASE/home"
mkdir -p "$HOME"
unset DBUS_SESSION_BUS_ADDRESS PASSWORD_STORE_DIR

# ============================================================================
# bws-token tests
# ============================================================================

header "bws-token: no arguments"

output=$(PATH="$DIR_ALL:$BASE_PATH" "$BWS_TOKEN_SCRIPT" 2>&1); rc=$?
assert_exit_code "exits 1 when called with no arguments" 1 "$rc"
assert_equals "prints usage to stderr" "usage: bws-token <handle>" "$output"

header "bws-token: macOS Keychain (security available first)"

output=$(PATH="$DIR_ALL:$BASE_PATH" "$BWS_TOKEN_SCRIPT" mac 2>&1); rc=$?
assert_exit_code "exits 0 when security found" 0 "$rc"
assert_equals "returns security token" "$SECURITY_TOKEN" "$output"

header "bws-token: fallback to secret-tool when security absent"

output=$(PATH="$DIR_NO_SEC:$BASE_PATH" "$BWS_TOKEN_SCRIPT" mac 2>&1); rc=$?
assert_exit_code "exits 0 when secret-tool found" 0 "$rc"
assert_equals "returns secret-tool token" "$SECRET_TOOL_TOKEN" "$output"

header "bws-token: fallback to pass when security and secret-tool absent"

output=$(PATH="$DIR_NO_LIBSEC:$BASE_PATH" "$BWS_TOKEN_SCRIPT" mac 2>&1); rc=$?
assert_exit_code "exits 0 when pass found" 0 "$rc"
assert_equals "returns pass token" "$PASS_TOKEN" "$output"

header "bws-token: no supported secret store on PATH"

output=$(PATH="$DIR_NONE:$BASE_PATH" "$BWS_TOKEN_SCRIPT" mac 2>&1); rc=$?
assert_exit_code "exits 1 when no store found" 1 "$rc"
assert_equals "prints no-store error message" "bws-token: no supported secret store found (need macOS security, secret-tool, or pass)" "$output"

# ============================================================================
# bwsx tests
# ============================================================================

header "bwsx: passes BWS_ACCESS_TOKEN and forwards args"

output=$(PATH="$DIR_BWS:$BASE_PATH" "$BWSX_SCRIPT" mac run --project-id test -- echo hello 2>&1); rc=$?
assert_exit_code "bwsx exits 0" 0 "$rc"
assert_equals "BWS_ACCESS_TOKEN injected" "BWS_ACCESS_TOKEN=$BWS_TOKEN_VALUE" "$(echo "$output" | grep '^BWS_ACCESS_TOKEN=')"
assert_equals "remaining args forwarded" "args: run --project-id test -- echo hello" "$(echo "$output" | grep '^args:')"

header "bws-token: store command fails (key not found)"

# security exits non-zero with no fallback — set -e propagates the store's exit code
output=$(PATH="$DIR_FAIL_SEC:$BASE_PATH" "$BWS_TOKEN_SCRIPT" mac 2>&1); rc=$?
if [[ "$rc" -ne 0 ]]; then
    ok "exits non-zero when store command fails (exit $rc)"
else
    fail "exits non-zero when store command fails — expected non-zero, got 0"
fi

header "bwsx: exits 1 when bws-token returns empty token"

output=$(PATH="$DIR_BWS_EMPTY:$BASE_PATH" "$BWSX_SCRIPT" mac run 2>&1); rc=$?
assert_exit_code "exits 1 on empty token" 1 "$rc"
assert_equals "prints empty-token error" "bwsx: empty token returned for handle 'mac'" "$output"

# ============================================================================
# Summary
# ============================================================================

echo ""
total=$((PASS + FAIL))
echo "Results: $PASS/$total passed, $FAIL failed"
echo ""
[[ $FAIL -eq 0 ]]
