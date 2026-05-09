#!/usr/bin/env bash
# Push sources to the server and rebuild there (Linux ELF target).
# Usage: scripts/deploy.sh user@host [/opt/cobill]

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
# /opt/cobill is owned by the cobill user, so we rsync through sudo.
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
ssh "${REMOTE}" "sudo chown -R cobill:cobill ${PREFIX} \
    && sudo chgrp -R www-data ${PREFIX}/data ${PREFIX}/pdf \
    && sudo chmod -R 2775 ${PREFIX}/data ${PREFIX}/pdf"

echo "==> Rebuilding on ${REMOTE}"
ssh "${REMOTE}" "cd ${PREFIX} \
    && sudo -u cobill make clean \
    && sudo -u cobill make build"

echo "==> Reloading Apache"
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
