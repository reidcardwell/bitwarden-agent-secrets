# Installing the official `bws` binary

This toolkit shells out to Bitwarden's official Secrets Manager CLI, `bws`. Install it from the **signed vendor release**, not `cargo`, not a third-party tap. For a secrets tool, binary provenance is part of the threat model.

## Download

Releases: <https://github.com/bitwarden/sdk-sm/releases>

Pick the asset for your platform:

| Platform | Asset suffix |
|----------|--------------|
| macOS (Apple Silicon) | `*-aarch64-apple-darwin` |
| macOS (Intel) | `*-x86_64-apple-darwin` |
| Linux (x86_64) | `*-x86_64-unknown-linux-gnu` |
| Linux (ARM64) | `*-aarch64-unknown-linux-gnu` |

## Install to `~/.local/bin`

```bash
# 1. Download the right archive for your arch from the releases page (above).
# 2. Verify the checksum against the release's published checksums.
# 3. Extract and place the binary:
unzip bws-*.zip            # or: tar xzf bws-*.tar.gz
install -m 0755 bws "$HOME/.local/bin/bws"

# 4. Confirm:
bws --version
```

Ensure `~/.local/bin` is on your `PATH`. If `bws` isn't found right after install, run `rehash` (zsh) or open a new shell tab.

## First-run note

The `bws` CLI keeps its own encrypted state under `~/.config/bws/state`. That is **bws's** store; never hand-write your access token into it. Your token belongs in the OS keychain (see [`operator-guide.md`](./operator-guide.md) → "Set up a NEW machine").
