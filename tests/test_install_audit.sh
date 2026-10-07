#!/usr/bin/env bash
# Checks are passed to eval in single quotes on purpose, so they expand late.
# shellcheck disable=SC2016,SC2034
# test_install_audit.sh: install.sh and bws-audit.sh against throwaway dirs.
# HOME, BIN_DEST and SKILL_DEST all point into a temp dir, so nothing real is
# read or written.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO/skills/bitwarden/scripts"
AUDIT="$SCRIPTS/bws-audit.sh"
WRAPPERS=(bws-token bwsx bw-token bw-unlock bwx bw-fill)

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" BIN_DEST="$T/bin" SKILL_DEST="$T/skills" INSTALL_SKILL=yes
mkdir -p "$HOME"

pass=0
fail=0
ok()  { echo "  PASS: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "--- install.sh ---"
"$REPO/install.sh" >"$T/install.out" 2>&1; rc=$?
check "installer exits 0" '[[ $rc -eq 0 ]]'
for w in "${WRAPPERS[@]}"; do
    check "$w installed as an executable copy" '[[ -x "$BIN_DEST/$w" && ! -L "$BIN_DEST/$w" ]] && cmp -s "$SCRIPTS/$w" "$BIN_DEST/$w"'
done
check "audit script is not put on PATH" '[[ ! -e "$BIN_DEST/bws-audit.sh" ]]'
check "skill installed with both references" '[[ -f "$SKILL_DEST/bitwarden/SKILL.md" && -f "$SKILL_DEST/bitwarden/references/secrets-manager.md" && -f "$SKILL_DEST/bitwarden/references/password-manager.md" ]]'
rm -f "$BIN_DEST/bwsx" && ln -s /nonexistent "$BIN_DEST/bwsx"
"$REPO/install.sh" >/dev/null 2>&1
check "re-run replaces a dangling symlink with a copy" '[[ -f "$BIN_DEST/bwsx" && ! -L "$BIN_DEST/bwsx" ]]'

echo "--- bws-audit.sh ---"
proj="$T/proj"
mkdir -p "$proj"
git -C "$proj" init -q

out="$("$AUDIT" "$proj" 2>&1)"
check "fresh install: every wrapper copy passes" '[[ $(grep -c "is an executable copy" <<<"$out") -eq 6 ]]'
check "missing default manifest is a WARN, not a FAIL" 'grep -q "WARN.*no manifest at $proj/secrets-manifest.yaml" <<<"$out" && ! grep -q "^\[FAIL\]" <<<"$out"'

printf 'connections:\n  app:\n    project: prod\n    env: APP_DB_DSN\nprojects:\n  prod: "00000000-0000-0000-0000-000000000000"\n' >"$proj/db-sync-manifest.yaml"
out="$("$AUDIT" --manifest db-sync-manifest.yaml "$proj" 2>&1)"; rc=$?
check "--manifest scans the named file" 'grep -q "PASS.*db-sync-manifest.yaml exists" <<<"$out"'
check "--manifest relative path resolves against the target" '[[ $rc -eq 0 ]]'

printf 'injections:\n  app:\n    project: prod\n    dsn: "mysql://u:p@db/app"\n' >"$T/abs.yaml"
out="$("$AUDIT" --manifest "$T/abs.yaml" "$proj" 2>&1)"; rc=$?
check "--manifest absolute path with an embedded DSN fails" '[[ $rc -ne 0 ]] && grep -q "FAIL.*:// value" <<<"$out"'

cp "$T/abs.yaml" "$proj/secrets-manifest.yaml"
out="$("$AUDIT" "$proj" 2>&1)"; rc=$?
check "default manifest with an embedded DSN fails" '[[ $rc -ne 0 ]] && grep -q "FAIL.*:// value" <<<"$out"'
rm -f "$proj/secrets-manifest.yaml"

echo 'export BW_SESSION=abc' >"$HOME/.bashrc"
out="$("$AUDIT" "$proj" 2>&1)"
check "BW_SESSION assignment in a profile fails" 'grep -q "FAIL.*Bitwarden credential assignment.*bashrc" <<<"$out"'
rm -f "$HOME/.bashrc"

echo '# edited' >>"$BIN_DEST/bwx"
out="$("$AUDIT" "$proj" 2>&1)"
check "edited installed copy is reported stale" 'grep -q "FAIL.*bwx is stale" <<<"$out"'

"$AUDIT" --manifest >/dev/null 2>&1; rc=$?
check "--manifest without a value exits 2" '[[ $rc -eq 2 ]]'
"$AUDIT" --bogus >/dev/null 2>&1; rc=$?
check "unknown flag exits 2" '[[ $rc -eq 2 ]]'

echo ""
echo "RESULT: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
