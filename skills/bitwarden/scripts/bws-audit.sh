#!/usr/bin/env bash
# bws-audit.sh: security audit for a bitwarden-agent-secrets setup
#
# Runs two kinds of checks:
#   MACHINE: the wrappers are installed correctly and no credential has leaked
#            into shell profiles or the bws state file.
#   PROJECT: the target project's manifest is credential-free and no BWS token
#            is committed or sitting in a .env.
#
# Usage:
#   bws-audit.sh [--manifest FILE] [TARGET_PROJECT_DIR]
#   TARGET_PROJECT_DIR defaults to the current directory. FILE defaults to
#   secrets-manifest.yaml; a relative FILE resolves against TARGET_PROJECT_DIR.
#   Installed copies are expected in ${BIN_DEST:-~/.local/bin}.
#
# Expected non-failures before first install:
#   - The wrapper copies are MISSING until install.sh has run. That's "setup
#     incomplete", not a security problem.
#   - ~/.config/bws/state may not exist until the bws CLI has run once (benign WARN).

set -euo pipefail

PASS=0
FAIL=0
WARN=0
pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
warn() { echo "[WARN] $1"; WARN=$((WARN + 1)); }

usage() { echo "usage: bws-audit.sh [--manifest FILE] [TARGET_PROJECT_DIR]" >&2; exit 2; }

MANIFEST_ARG="secrets-manifest.yaml"
TARGET_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest) [[ $# -ge 2 && -n "$2" ]] || usage; MANIFEST_ARG="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) usage ;;
        *) [[ -z "$TARGET_ARG" ]] || usage; TARGET_ARG="$1"; shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(cd "${TARGET_ARG:-$PWD}" && pwd)"
BIN_DIR="${BIN_DEST:-$HOME/.local/bin}"
if [[ "$MANIFEST_ARG" == /* ]]; then MANIFEST="$MANIFEST_ARG"; else MANIFEST="$TARGET/$MANIFEST_ARG"; fi
MANIFEST_NAME="$(basename "$MANIFEST")"

echo "=== bitwarden-agent-secrets audit ==="
echo "Wrappers: $SCRIPT_DIR"
echo "Target project: $TARGET"
echo ""

# ── (a) installed helper copies ───────────────────────────────────────────────
echo "--- (a) installed wrapper copies ($BIN_DIR) ---"
for bin in bws-token bwsx bw-token bw-unlock bwx bw-fill; do
    bin_path="$BIN_DIR/$bin"
    src_path="$SCRIPT_DIR/$bin"
    if [[ -L "$bin_path" ]]; then
        fail "$bin_path is a symlink (legacy/dangling) — reinstall the wrappers as copies"
    elif [[ ! -e "$bin_path" ]]; then
        fail "$bin_path does not exist (install the wrappers)"
    elif [[ ! -x "$bin_path" ]]; then
        fail "$bin_path exists but is not executable"
    elif [[ -f "$src_path" ]] && ! cmp -s "$src_path" "$bin_path"; then
        fail "$bin_path is stale — differs from $src_path (reinstall the wrappers)"
    else
        pass "$bin_path is an executable copy of $src_path"
    fi
done
echo ""

# ── (b) manifest secret-free scan ─────────────────────────────────────────────
echo "--- (b) $MANIFEST_NAME secret-free scan ---"
if [[ ! -f "$MANIFEST" ]]; then
    warn "no manifest at $MANIFEST (skipping manifest scan)"
else
    pass "$MANIFEST_NAME exists"
    if grep -E '^[[:space:]]+[a-zA-Z_]+:[[:space:]]+"?[^"]*://[^"]*"?' "$MANIFEST" | grep -vE '^[[:space:]]*#' | grep -q '.'; then
        fail "manifest contains a :// value (possible embedded credential/DSN)"
    else
        pass "no :// patterns in manifest values"
    fi
    CRED_KEYWORDS='password|passwd|secret|token|credential|apikey|api_key|access_key|private_key'
    if grep -iE "($CRED_KEYWORDS)[[:space:]]*:" "$MANIFEST" | grep -vE '^[[:space:]]*#' | grep -q '.'; then
        fail "manifest contains a credential keyword in a key"
    else
        pass "no credential keywords in manifest"
    fi
fi
echo ""

# ── (c) token leak: shell profiles + bws state perms ──────────────────────────
echo "--- (c) shell profile + config scan ---"
for profile in ~/.zshrc ~/.bashrc ~/.bash_profile ~/.profile; do
    expanded="${profile/#\~/$HOME}"
    [[ -f "$expanded" ]] || continue
    if grep -E '(BWS_ACCESS_TOKEN|BW_SESSION|BW_CLIENTSECRET|BW_PASSWORD|BW_MASTER)[[:space:]]*=' "$expanded" 2>/dev/null | grep -qv '^[[:space:]]*#'; then
        fail "Bitwarden credential assignment (BWS_ACCESS_TOKEN/BW_SESSION/BW_CLIENTSECRET/BW_PASSWORD/BW_MASTER) found in $profile"
    else
        pass "no Bitwarden credential assignment in $profile"
    fi
done
BWS_STATE="$HOME/.config/bws/state"
if [[ -e "$BWS_STATE" ]]; then
    perms="$(stat -c '%a' "$BWS_STATE" 2>/dev/null || stat -f '%OLp' "$BWS_STATE" 2>/dev/null || echo 'unknown')"
    if [[ "$perms" == "600" ]]; then
        pass "$BWS_STATE permissions are 0600"
    else
        warn "$BWS_STATE permissions are $perms (expected 0600)"
    fi
else
    warn "$BWS_STATE does not exist (bws CLI may not have run yet)"
fi
echo ""

# ── (d) target repo git grep for tokens ───────────────────────────────────────
echo "--- (d) target repo token scan ---"
if [[ -d "$TARGET/.git" ]] && command -v git &>/dev/null; then
    if git -C "$TARGET" grep -iE '0\.[0-9a-fA-F-]{30,}\.[A-Za-z0-9+/]{20,}' -- ':!*.md' 2>/dev/null | grep -q .; then
        fail "possible BWS token pattern found in tracked files under $TARGET"
    else
        pass "no BWS token pattern in tracked files"
    fi
else
    warn "$TARGET is not a git repo — skipping tracked-file scan"
fi
echo ""

# ── (e) .env token scan ───────────────────────────────────────────────────────
echo "--- (e) .env token scan ---"
env_files=()
while IFS= read -r f; do env_files+=("$f"); done \
    < <(find "$TARGET" \( -name '.env' -o -name '.env.*' \) 2>/dev/null | grep -v '/\.git/')
if [[ ${#env_files[@]} -eq 0 ]]; then
    pass "no .env files under $TARGET"
else
    token_found=0
    for env_file in "${env_files[@]}"; do
        if grep -E '=[[:space:]]*[0-9]+\.[0-9a-fA-F-]{30,}\.[A-Za-z0-9+/]{20,}' "$env_file" 2>/dev/null | grep -qv '^[[:space:]]*#'; then
            fail ".env may contain a BWS access token: $env_file"
            token_found=1
        fi
    done
    [[ $token_found -eq 0 ]] && pass "no BWS token values in .env files"
fi
echo ""

# ── summary ───────────────────────────────────────────────────────────────────
echo "=========================================="
echo "AUDIT SUMMARY: PASS=$PASS  FAIL=$FAIL  WARN=$WARN"
if [[ $FAIL -eq 0 ]]; then
    echo "Result: CLEAN (all checks passed or warned only)"
    exit 0
else
    echo "Result: ISSUES FOUND — review FAIL entries above"
    exit 1
fi
