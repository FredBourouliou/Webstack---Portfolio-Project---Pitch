#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu 22.04 server. Idempotent.
# Run on the server: sudo bash deploy/setup-server.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run me as root (sudo bash deploy/setup-server.sh)." >&2
    exit 1
fi

INSTALL_ROOT="/opt/cobill"
DATA_ROOT="${INSTALL_ROOT}/data"
PDF_ROOT="${INSTALL_ROOT}/pdf"
WEB_ROOT="${INSTALL_ROOT}/web"
BIN_ROOT="${INSTALL_ROOT}/bin"
APP_USER="cobill"

log() { printf "\n\033[1;36m==>\033[0m %s\n" "$*"; }

# System packages
log "Installing GnuCOBOL, Ghostscript, Apache, certbot"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    gnucobol \
    ghostscript \
    apache2 \
    certbot python3-certbot-apache \
    curl \
    jq \
    rsync \
    make \
    git \
    ca-certificates \
    ufw

# Apache modules
log "Enabling Apache modules"
a2enmod cgi headers rewrite ssl >/dev/null
a2dismod -q mpm_event 2>/dev/null || true
a2enmod  -q mpm_prefork  # CGI is fork-per-request, prefork fits

# App user
if ! id "${APP_USER}" >/dev/null 2>&1; then
    log "Creating system user ${APP_USER}"
    useradd --system --home-dir "${INSTALL_ROOT}" \
            --shell /usr/sbin/nologin "${APP_USER}"
fi

# Filesystem layout
log "Creating ${INSTALL_ROOT} layout"
mkdir -p "${INSTALL_ROOT}" "${BIN_ROOT}" "${DATA_ROOT}" "${PDF_ROOT}" \
         "${WEB_ROOT}" "${INSTALL_ROOT}/src/postscript" \
         "${INSTALL_ROOT}/lib"

# Apache (www-data) reads source, writes data and generated PDFs.
chown -R "${APP_USER}:${APP_USER}" "${INSTALL_ROOT}"
chgrp -R www-data "${DATA_ROOT}" "${PDF_ROOT}"
chmod -R 2775 "${DATA_ROOT}" "${PDF_ROOT}"

# Symlinks: COBOL binaries use cwd-relative paths like "data/clients.dat"
# but Apache runs them with cwd=/opt/cobill/bin/.
log "Wiring relative-path symlinks in ${BIN_ROOT}"
ln -sfn "${DATA_ROOT}"          "${BIN_ROOT}/data"
ln -sfn "${PDF_ROOT}"           "${BIN_ROOT}/pdf"
ln -sfn "${INSTALL_ROOT}/src"   "${BIN_ROOT}/src"
ln -sfn "${INSTALL_ROOT}/lib"   "${BIN_ROOT}/lib"

# Apache vhost
VHOST_FILE="/etc/apache2/sites-available/cobill.conf"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "${SCRIPT_DIR}/cobill.conf" ]]; then
    log "Installing Apache vhost"
    install -m 0644 "${SCRIPT_DIR}/cobill.conf" "${VHOST_FILE}"
else
    echo "(skipped vhost install: cobill.conf not in ${SCRIPT_DIR})"
fi

a2dissite -q 000-default 2>/dev/null || true
a2ensite -q cobill

# UFW: explicit port numbers, allow SSH first to avoid lockout.
log "UFW: allow 22/80/443 then enable"
ufw allow 22/tcp comment 'ssh'    || true
ufw allow 80/tcp comment 'http'   || true
ufw allow 443/tcp comment 'https' || true
ufw --force enable                || true
ufw status verbose                || true

# Auth credential: generate a random password, hash with sha512crypt,
# persist only the hash. Plaintext is printed once.
ENV_FILE="/etc/cobill/cobill.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    log "Generating /etc/cobill/cobill.env"
    mkdir -p /etc/cobill
    PASS="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
    HASH="$(openssl passwd -6 "${PASS}")"
    # Single-quote the hash so /etc/apache2/envvars sourcing does not
    # expand the $ in $6$salt$... as bash positional parameters.
    cat > "${ENV_FILE}" <<EOF
COBILL_AUTH_HASH='${HASH}'
EOF
    chown root:www-data "${ENV_FILE}"
    chmod 0640 "${ENV_FILE}"
    echo
    echo "  ----------------------------------------------------------"
    echo "  Initial admin password (shown once, save it now):"
    echo "  ${PASS}"
    echo "  ----------------------------------------------------------"
fi

# Make Apache source the env file at startup.
ENVVARS_FILE="/etc/apache2/envvars"
if ! grep -q "cobill.env" "${ENVVARS_FILE}"; then
    log "Wiring /etc/cobill/cobill.env into ${ENVVARS_FILE}"
    cat >> "${ENVVARS_FILE}" <<'EOF'

if [ -f /etc/cobill/cobill.env ]; then
    set -a
    . /etc/cobill/cobill.env
    set +a
fi
EOF
fi

# Restart Apache
log "Reloading Apache"
apachectl configtest
systemctl reload apache2 || systemctl restart apache2

cat <<MSG

Setup complete.

Next:
    scripts/deploy.sh user@${HOSTNAME:-your-host}
    sudo certbot --apache -d cobill.your-domain.tld
    curl -i https://cobill.your-domain.tld/login.html

MSG
