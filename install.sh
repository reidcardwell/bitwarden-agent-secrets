#!/usr/bin/env bash
# install.sh: deploy the bitwarden-agent-secrets wrappers (and optionally the
# Claude Code skill).
#
# Copies skills/bitwarden/scripts/* (except the audit) to ~/.local/bin as
# executable COPIES, not symlinks, so the tools survive moving or deleting this
# repo. Optionally installs the bitwarden skill into ~/.claude/skills/.
#
# Idempotent: re-running refreshes the copies in place.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_ROOT/skills/bitwarden"
BIN_DEST="${BIN_DEST:-$HOME/.local/bin}"
SKILL_DEST="${SKILL_DEST:-$HOME/.claude/skills}"
INSTALL_SKILL="${INSTALL_SKILL:-ask}"   # ask | yes | no
WRAPPERS=(bws-token bwsx bw-token bw-unlock bwx bw-fill)

info() { echo "  $1"; }
ok()   { echo "[ok] $1"; }

echo "=== bitwarden-agent-secrets installer ==="
echo "Source: $REPO_ROOT"
echo ""

# ── wrappers → ~/.local/bin ───────────────────────────────────────────────────
mkdir -p "$BIN_DEST"
for bin in "${WRAPPERS[@]}"; do
    rm -f "$BIN_DEST/$bin"
    install -m 0755 "$SKILL_SRC/scripts/$bin" "$BIN_DEST/$bin"
    ok "installed $BIN_DEST/$bin"
done

case ":$PATH:" in
    *":$BIN_DEST:"*) : ;;
    *) info "NOTE: $BIN_DEST is not on your PATH. Add it to your shell profile." ;;
esac

# ── official CLI presence checks ──────────────────────────────────────────────
if command -v bws &>/dev/null; then
    ok "bws found: $(command -v bws)"
else
    info "NOTE: 'bws' (Secrets Manager CLI) is not on PATH; see docs/install-bws.md."
fi
if command -v bw &>/dev/null; then
    ok "bw found: $(command -v bw)"
else
    info "NOTE: 'bw' (Password Manager CLI) is not on PATH; needed only for the browser-login flow."
fi

# ── optional: Claude Code skill ───────────────────────────────────────────────
if [[ "$INSTALL_SKILL" == "ask" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Install the Claude Code 'bitwarden' skill into $SKILL_DEST? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] && INSTALL_SKILL=yes || INSTALL_SKILL=no
    else
        INSTALL_SKILL=no
    fi
fi

if [[ "$INSTALL_SKILL" == "yes" ]]; then
    rm -rf "${SKILL_DEST:?}/bitwarden"
    mkdir -p "$SKILL_DEST/bitwarden"
    cp -R "$SKILL_SRC/." "$SKILL_DEST/bitwarden/"
    ok "installed skill → $SKILL_DEST/bitwarden"
    if [[ -d "$SKILL_DEST/bws-secrets" ]]; then
        info "NOTE: the old 'bws-secrets' skill is still at $SKILL_DEST/bws-secrets; 'bitwarden' replaces it, so remove it."
    fi
else
    info "Skipped skill install (set INSTALL_SKILL=yes to force, or copy skills/bitwarden/ yourself)."
fi

echo ""
echo "Done. Verify with:  skills/bitwarden/scripts/bws-audit.sh"
