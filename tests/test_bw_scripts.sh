#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/bitwarden/scripts" && pwd)"
SCRIPTS=(bw-token bw-unlock bwx bw-fill)

pass=0
fail=0

ok() { echo "  PASS: $1"; ((++pass)); }
fail_check() { echo "  FAIL: $1"; ((++fail)); }

cleanup() {
    if [[ $fail -gt 0 ]]; then
        echo ""
        echo "RESULT: $pass passed, $fail failed"
        exit 1
    else
        echo ""
        echo "RESULT: all $pass checks passed"
    fi
}
trap cleanup EXIT

for script in "${SCRIPTS[@]}"; do
    path="$SCRIPTS_DIR/$script"
    echo "--- $script ---"

    if [[ -f "$path" ]]; then
        ok "exists"
    else
        fail_check "exists: $path not found"
        continue
    fi

    if head -1 "$path" | grep -qF '#!/usr/bin/env bash'; then
        ok "shebang"
    else
        fail_check "shebang: first line is not '#!/usr/bin/env bash'"
    fi

    if [[ -x "$path" ]]; then
        ok "executable"
    else
        fail_check "executable: $path is not executable"
    fi

    if bash -n "$path" 2>/dev/null; then
        ok "bash -n syntax"
    else
        fail_check "bash -n syntax: $path has syntax errors"
    fi

    if grep -q 'set -euo pipefail' "$path"; then
        ok "set -euo pipefail"
    else
        fail_check "set -euo pipefail: not found in $path"
    fi

    if "$path" >/dev/null 2>&1; then
        fail_check "no-args exit non-zero: exited 0 (expected non-zero)"
    else
        ok "no-args exit non-zero"
    fi
done

# bw-fill behavior against stub clipboard tools. DISPLAY points at a dead server so a
# stub miss can never reach the real clipboard.
echo "--- bw-fill clipboard paths (stubbed) ---"
stub_root="$(mktemp -d)"
trap 'rm -rf "$stub_root"; cleanup' EXIT
make_stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$1"; chmod +x "$1"; }

run_fill() { # <tool> <env...> -- <bw-fill args...>
    local tool="$1"; shift
    local dir="$stub_root/$tool"; rm -rf "$dir"; mkdir -p "$dir"
    make_stub "$dir/$tool" "{ echo \"args:\$*\"; echo \"stdin:\$(cat)\"; echo \"display:\$DISPLAY\"; } >>\"$dir/log\""
    make_stub "$dir/bw-unlock" 'echo fake-session'
    make_stub "$dir/bw" '[[ "$*" == "get password item-1" ]] && printf "fixture-pw"'
    local envs=(); while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
    env -u WAYLAND_DISPLAY DISPLAY=:99 ${envs[@]+"${envs[@]}"} PATH="$dir:/usr/bin:/bin" "$SCRIPTS_DIR/bw-fill" "$@" >"$dir/out" 2>&1
}

check_fill() { # <label> <tool> <expected-out> <expected-log-regex> <env...> -- <args...>
    local label="$1" tool="$2" want_out="$3" want_log="$4"; shift 4
    if run_fill "$tool" "$@" && [[ "$(cat "$stub_root/$tool/out")" == "$want_out" ]] \
        && grep -Pzq "$want_log" "$stub_root/$tool/log"; then
        ok "$label"
    else
        fail_check "$label: out=[$(cat "$stub_root/$tool/out" 2>/dev/null)] log=[$(tr '\n' '|' <"$stub_root/$tool/log" 2>/dev/null)]"
    fi
}

check_fill "xclip copy (password off stdout)" xclip copied 'args:-selection clipboard\nstdin:fixture-pw\n' -- h item-1
check_fill "xclip --clear empties clipboard" xclip cleared 'args:-selection clipboard\nstdin:\n' -- --clear
check_fill "wl-copy copy under Wayland" wl-copy copied 'args:\nstdin:fixture-pw\n' WAYLAND_DISPLAY=wayland-9 -- h item-1
check_fill "wl-copy --clear under Wayland" wl-copy cleared 'args:--clear\n' WAYLAND_DISPLAY=wayland-9 -- --clear
check_fill "pbcopy --clear empties clipboard" pbcopy cleared 'args:\nstdin:\n' -- --clear
if [[ "$(uname -s)" != "Darwin" && -S /tmp/.X11-unix/X0 ]]; then
    check_fill "headless shell falls back to DISPLAY=:0" xclip cleared 'display::0\n' DISPLAY= -- --clear
fi

if "$SCRIPTS_DIR/bw-fill" --clear extra >/dev/null 2>&1; then
    fail_check "--clear with extra args exits non-zero"
else
    ok "--clear with extra args exits non-zero"
fi

if command -v shellcheck &>/dev/null; then
    echo "--- shellcheck ---"
    paths=()
    for script in "${SCRIPTS[@]}"; do
        paths+=("$SCRIPTS_DIR/$script")
    done
    if shellcheck "${paths[@]}"; then
        ok "shellcheck clean"
    else
        echo "  NOTE: shellcheck reported issues (non-fatal)"
    fi
else
    echo "--- shellcheck: not installed, skipping (non-fatal) ---"
fi
