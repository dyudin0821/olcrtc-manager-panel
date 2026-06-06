#!/usr/bin/env bash
set -euo pipefail

random_hex() {
    local bytes="${1:-16}"
    od -An -N"$bytes" -tx1 /dev/urandom | tr -d ' \n'
}

CONFIG_DIR="${CONFIG_DIR:-/etc/olcrtc-manager}"
CONFIG_PATH="${CONFIG_PATH:-${CONFIG_DIR}/config.json}"
TLS_CERT="${TLS_CERT_PATH:-${CONFIG_DIR}/tls.crt}"
TLS_KEY="${TLS_KEY_PATH:-${CONFIG_DIR}/tls.key}"
PANEL_ENV="${PANEL_ENV_PATH:-${CONFIG_DIR}/panel.env}"
PANEL_ADDR="${PANEL_ADDR:-0.0.0.0}"
OLCRTC_PATH="${OLCRTC_PATH:-/usr/local/bin/olcrtc}"

mkdir -p "${CONFIG_DIR}"

# Load panel environment file if present
if [ -f "${PANEL_ENV}" ]; then
    set -a
    # shellcheck source=/dev/null
    . "${PANEL_ENV}"
    set +a
fi

# Generate self-signed TLS certificate if not provided
if [ ! -f "${TLS_CERT}" ] || [ ! -f "${TLS_KEY}" ]; then
    echo "[entrypoint] Generating self-signed TLS certificate..."
    CERT_IP="${PANEL_CERT_IP:-}"
    SAN="IP:127.0.0.1,DNS:localhost"
    if [ -n "${CERT_IP}" ]; then
        SAN="${SAN},IP:${CERT_IP}"
    fi
    openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes \
        -keyout "${TLS_KEY}" \
        -out    "${TLS_CERT}" \
        -subj   "/CN=olcrtc-manager" \
        -addext "subjectAltName=${SAN}" \
        2>/dev/null
    chmod 0600 "${TLS_KEY}"
    chmod 0644 "${TLS_CERT}"
    echo "[entrypoint] TLS certificate written to ${CONFIG_DIR}"
fi

# Generate panel.env with credentials on first run
_FIRST_RUN=0
if [ ! -f "${PANEL_ENV}" ]; then
    _FIRST_RUN=1
    _ADMIN_USER="${OLCRTC_MANAGER_USER:-admin$(random_hex 3)}"
    _ADMIN_PASS="${OLCRTC_MANAGER_PASS:-$(random_hex 16)}"
    _ADMIN_PATH="${OLCRTC_MANAGER_ADMIN_PATH:-/admin-$(random_hex 4)}"
    case "${_ADMIN_PATH}" in
        /*) ;;
        *) _ADMIN_PATH="/${_ADMIN_PATH}" ;;
    esac
    echo "[entrypoint] Generating panel.env at ${PANEL_ENV}"
    cat > "${PANEL_ENV}" <<EOF
OLCRTC_MANAGER_USER='${_ADMIN_USER}'
OLCRTC_MANAGER_PASS='${_ADMIN_PASS}'
OLCRTC_MANAGER_ADMIN_PATH='${_ADMIN_PATH}'
OLCRTC_MANAGER_TLS_CERT='${TLS_CERT}'
OLCRTC_MANAGER_TLS_KEY='${TLS_KEY}'
EOF
    chmod 0600 "${PANEL_ENV}"
    # Load the newly created env file
    set -a
    # shellcheck source=/dev/null
    . "${PANEL_ENV}"
    set +a
fi

# Create a minimal default config if none exists
if [ ! -f "${CONFIG_PATH}" ]; then
    echo "[entrypoint] Creating default config at ${CONFIG_PATH}"
    cat > "${CONFIG_PATH}" <<'EOF'
{
  "version": 1,
  "name": "OlcRTC VPS",
  "port": 8443,
  "clients": []
}
EOF
    chmod 0600 "${CONFIG_PATH}"
fi

# Print access info (always show, credentials only on first run)
_DISPLAY_HOST="${PANEL_CERT_IP:-localhost}"
echo "[entrypoint] Access URL: https://${_DISPLAY_HOST}:8443${OLCRTC_MANAGER_ADMIN_PATH:-/admin}"
if [ "${_FIRST_RUN}" = "1" ]; then
    echo "[entrypoint] Username:   ${_ADMIN_USER}"
    echo "[entrypoint] Password:   ${_ADMIN_PASS}"
    echo "[entrypoint] TLS uses a self-signed certificate; browsers may ask you to accept it."
fi

export OLCRTC_PATH
export OLCRTC_MANAGER_ADDR="${PANEL_ADDR}"

exec /usr/local/bin/olcrtc-manager -config "${CONFIG_PATH}"
