#!/usr/bin/env bash
set -euo pipefail

identity="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel 2>/dev/null || (cd "$script_dir/.." && pwd))"
settings_file="$repo_root/script/codesign-settings.mk"

if [ "$identity" = "-" ]; then
    exit 0
fi

if [ -z "$identity" ]; then
    identity="$(git -C "$repo_root" config --get winmux.codesignIdentity 2>/dev/null || true)"
fi

if [ -z "$identity" ]; then
    identity="$(sed -n 's/^WINMUX_CODESIGN_IDENTITY[[:space:]]*=[[:space:]]*//p' "$settings_file" 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$identity" ]; then
    identity="$(git -C "$repo_root" show HEAD:script/codesign-settings.mk 2>/dev/null | sed -n 's/^WINMUX_CODESIGN_IDENTITY[[:space:]]*=[[:space:]]*//p' | head -n 1 || true)"
fi

if [ -z "$identity" ]; then
    cat >&2 <<EOF
error: Code signing identity could not be resolved from Git.

Set git config winmux.codesignIdentity or pass CODESIGN_IDENTITY explicitly.
EOF
    exit 1
fi

if security find-identity -v -p codesigning | grep -F "$identity" >/dev/null; then
    exit 0
fi

cat >&2 <<EOF
error: Code signing identity is not available in this keychain:
  $identity

The identity name was retrieved from Git, but macOS can only sign when the
matching, unexpired certificate and private key are installed locally.
EOF
exit 1
