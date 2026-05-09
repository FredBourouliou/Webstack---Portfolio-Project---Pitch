#!/usr/bin/env bash
# Generate a sha512crypt hash for COBILL_AUTH_HASH.
# Usage: scripts/gen-auth-hash.sh        (prompts, no echo)
#        scripts/gen-auth-hash.sh 'pwd'  (one-shot)

set -euo pipefail

if [[ $# -ge 1 ]]; then
    pw="$1"
else
    read -r -s -p "Password: " pw; echo
    read -r -s -p "Confirm:  " pw2; echo
    [[ "$pw" == "$pw2" ]] || { echo "Mismatch." >&2; exit 1; }
fi

[[ -n "$pw" ]] || { echo "Empty password." >&2; exit 1; }

openssl passwd -6 "$pw"
