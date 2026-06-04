#!/usr/bin/env bash
# install.sh — deploy bws-agent-secrets helpers (and optionally the Claude Code skill)
#
# Copies bin/bws-token and bin/bwsx to ~/.local/bin as executable COPIES
# (not symlinks), so the tools survive moving or deleting this repo.
# Optionally installs the bws-secrets skill into ~/.claude/skills/.
#
# Idempotent: re-running refreshes the copies in place.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DEST="${BIN_DEST:-$HOME/.local/bin}"
SKILL_DEST="${SKILL_DEST:-$HOME/.claude/skills}"
INSTALL_SKILL="${INSTALL_SKILL:-ask}"   # ask | yes | no

info() { echo "  $1"; }
ok()   { echo "[ok] $1"; }

echo "=== bws-agent-secrets installer ==="
echo "Source: $REPO_ROOT"
echo ""

# ── helpers → ~/.local/bin ────────────────────────────────────────────────────
mkdir -p "$BIN_DEST"
for bin in bws-token bwsx; do
    install -m 0755 "$REPO_ROOT/bin/$bin" "$BIN_DEST/$bin"
    ok "installed $BIN_DEST/$bin"
done

case ":$PATH:" in
    *":$BIN_DEST:"*) : ;;
    *) info "NOTE: $BIN_DEST is not on your PATH. Add it to your shell profile." ;;
esac

# ── bws binary presence check ─────────────────────────────────────────────────
if command -v bws &>/dev/null; then
    ok "bws found: $(command -v bws)"
else
    info "WARNING: the official 'bws' binary is not on PATH."
    info "Install it from https://github.com/bitwarden/sdk-sm/releases"
    info "See docs/install-bws.md for per-OS instructions."
fi

# ── optional: Claude Code skill ───────────────────────────────────────────────
if [[ "$INSTALL_SKILL" == "ask" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Install the Claude Code 'bws-secrets' skill into $SKILL_DEST? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] && INSTALL_SKILL=yes || INSTALL_SKILL=no
    else
        INSTALL_SKILL=no
    fi
fi

if [[ "$INSTALL_SKILL" == "yes" ]]; then
    mkdir -p "$SKILL_DEST/bws-secrets"
    cp -R "$REPO_ROOT/skills/bws-secrets/." "$SKILL_DEST/bws-secrets/"
    ok "installed skill → $SKILL_DEST/bws-secrets"
else
    info "Skipped skill install (set INSTALL_SKILL=yes to force, or copy skills/bws-secrets/ yourself)."
fi

echo ""
echo "Done. Verify with:  scripts/bws-audit.sh"
