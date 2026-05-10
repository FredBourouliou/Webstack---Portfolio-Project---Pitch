#!/usr/bin/env bash
# gen-auth-hash.sh — produce a sha512crypt hash for COBILL_AUTH_HASH.
#
# Usage: scripts/gen-auth-hash.sh         (interactive, no echo)
#        scripts/gen-auth-hash.sh 'pwd'   (one-shot, scriptable)
#
# Output is a single line that can be pasted into the value of
# COBILL_AUTH_HASH in /etc/cobill/cobill.env (production) or
# Cobill/.env (dev). Apache PassEnv exposes this variable to
# the auth.cob CGI binary at request time, which calls libc
# crypt(3) to verify the submitted password against the hash.
#
# Why sha512crypt and not bcrypt / argon2?
#   - GnuCOBOL has no native bcrypt or argon2 binding.
#   - sha512crypt is what Linux uses for /etc/shadow ($6$...),
#     which means libc already ships with the crypt(3) needed
#     to verify the hash. Zero extra dependency.
#   - The hash format includes its own salt + 5000 rounds, so
#     comparing against a different submitted password runs the
#     full algorithm again. Not as slow as bcrypt or argon2,
#     but enough for a single-user app where the login endpoint
#     is rate-limited at the network layer.
#
# IMPORTANT: when pasting the result into a .env file, wrap it
# in SINGLE quotes. The hash contains "$" characters which bash
# would otherwise interpret as variable expansions when the env
# file is sourced. See cobill.conf for the documented gotcha.

set -euo pipefail

# Accept either an inline password (for scripting) or prompt
# interactively without echoing the input.
if [[ $# -ge 1 ]]; then
    pw="$1"
else
    # -s = silent (no echo), -r = raw (no backslash processing).
    read -r -s -p "Password: " pw; echo
    read -r -s -p "Confirm:  " pw2; echo
    [[ "$pw" == "$pw2" ]] || { echo "Mismatch." >&2; exit 1; }
fi

# Reject empty passwords explicitly. crypt(3) would silently
# produce a hash for them otherwise, which is exactly the kind
# of footgun we want to avoid in a credential setup tool.
[[ -n "$pw" ]] || { echo "Empty password." >&2; exit 1; }

# -6 selects sha512crypt ($6$...). openssl picks a random
# 16-character salt on its own.
openssl passwd -6 "$pw"
