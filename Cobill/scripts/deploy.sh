#!/usr/bin/env bash
# deploy.sh — push the local source tree to a target server and
# rebuild the COBOL binaries there.
#
# Usage: scripts/deploy.sh user@host [/opt/cobill]
#
# Why a build-on-target deploy?
# The COBOL binaries are native ELF (compiled from GnuCOBOL ->
# C -> gcc). Cross-compiling from macOS to Linux is doable but
# brittle; building on the server is one less moving piece.
#
# Steps performed by this script:
#   1. rsync the source tree (Makefile, src/, web/, scripts/,
#      deploy/, lib/) into PREFIX on the target host. The
#      remote rsync runs through sudo because PREFIX is owned
#      by the cobill system user (set up by deploy/setup-server.sh).
#   2. Restore ownership and group bits so cobill owns
#      everything, www-data can read/write data/ and pdf/, and
#      the SGID bit on those directories keeps that group
#      inheritance going for files created later.
#   3. Run `make clean` + `make build` as the cobill user so
#      every binary is freshly compiled against the current
#      sources.
#   4. Reload Apache (graceful: existing requests finish,
#      workers pick up the new binaries on their next exec).
#
# Excludes:
#   - bin/, data/, pdf/        runtime / data, never deployed
#   - .DS_Store, *.swp         editor cruft
#   - scripts/dev-server.py    local-only Python helper
#
# Health check: a small curl recipe is printed at the end. Note
# that smoke-test.sh is NOT safe on a populated server: it wipes
# the data directory before running.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 user@host [remote-prefix]" >&2
    exit 1
fi

REMOTE="$1"
PREFIX="${2:-/opt/cobill}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "${ROOT}"

echo "==> Syncing code to ${REMOTE}:${PREFIX}"
# /opt/cobill is owned by the cobill user; rsync needs sudo on
# the remote end to write there.
rsync -avz --delete --rsync-path="sudo rsync" \
    --exclude='/bin/*' \
    --include='/bin/.gitkeep' \
    --exclude='/data/*' \
    --include='/data/.gitkeep' \
    --exclude='/pdf/*' \
    --include='/pdf/.gitkeep' \
    --exclude='.DS_Store' \
    --exclude='*.swp' \
    --exclude='/scripts/dev-server.py' \
    Makefile src web scripts deploy lib \
    "${REMOTE}:${PREFIX}/"

echo "==> Restoring ownership"
# chown -R cobill:cobill   the deployer wrote everything as root
#                          via "sudo rsync"; switch the owner back.
# chgrp -R www-data data/  Apache reads/writes through www-data.
# chmod 2775 data/ pdf/    rwxrwsr-x: SGID propagates group to
#                          files created later in those dirs.
ssh "${REMOTE}" "sudo chown -R cobill:cobill ${PREFIX} \
    && sudo chgrp -R www-data ${PREFIX}/data ${PREFIX}/pdf \
    && sudo chmod -R 2775 ${PREFIX}/data ${PREFIX}/pdf"

echo "==> Rebuilding on ${REMOTE}"
# Run make as the cobill user so the resulting binaries are
# owned by cobill (matches the install layout).
ssh "${REMOTE}" "cd ${PREFIX} \
    && sudo -u cobill make clean \
    && sudo -u cobill make build"

echo "==> Reloading Apache"
# reload (graceful) rather than restart: in-flight requests
# keep their current binaries, new requests get the new ones.
ssh "${REMOTE}" "sudo systemctl reload apache2"

echo
echo "Deployed."
echo
echo "Quick health check (read-only, safe on populated data):"
echo "    curl -sS -i \$(ssh ${REMOTE} 'echo http://localhost')/login.html | head -3"
echo "    curl -sS -i -o /dev/null -w 'cgi gate: %{http_code}\\n' \\"
echo "        \$(ssh ${REMOTE} 'echo http://localhost')/cgi-bin/client?action=list"
echo
echo "(don't run smoke-test.sh on prod, it wipes data)"
