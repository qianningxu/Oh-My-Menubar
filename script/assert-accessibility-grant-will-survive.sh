#!/usr/bin/env bash
set -euo pipefail

candidate_executable="${1:?candidate executable path is required}"
bundle_id="${2:-com.zimengxiong.winmux}"
install_path="${3:-$candidate_executable}"
tcc_db="/Library/Application Support/com.apple.TCC/TCC.db"

if [ "${ALLOW_TCC_REAUTH:-0}" = "1" ]; then
    exit 0
fi

req_file="$(mktemp)"
trap 'rm -f "$req_file"' EXIT

if ! sqlite3 "$tcc_db" "select writefile('$req_file', csreq) from access where service = 'kTCCServiceAccessibility' and client = '$bundle_id' and auth_value = 2 limit 1;" >/dev/null; then
    echo "Could not read the existing Accessibility grant from $tcc_db" >&2
    exit 65
fi

if [ ! -s "$req_file" ]; then
    cat >&2 <<EOF
No existing enabled Accessibility grant found for $bundle_id.
Refusing to install $install_path because the rebuilt app would require macOS authorization.
EOF
    exit 65
fi

if ! codesign --ignore-resources -R "$req_file" --verify "$candidate_executable" >/dev/null 2>&1; then
    requirement_text="$(csreq -r "$req_file" -t 2>/dev/null || true)"
    cat >&2 <<EOF
The rebuilt app does not satisfy the already-authorized Accessibility requirement.
Existing requirement: ${requirement_text:-unreadable}

Refusing to install $install_path because this build would force macOS
Accessibility re-authorization.
EOF
    exit 65
fi
