#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/olcrtc-manager}"
CONFIG_PATH="${CONFIG_PATH:-${CONFIG_DIR}/config.json}"
TLS_CERT="${TLS_CERT_PATH:-${CONFIG_DIR}/tls.crt}"
TLS_KEY="${TLS_KEY_PATH:-${CONFIG_DIR}/tls.key}"
PANEL_ENV="${PANEL_ENV_PATH:-${CONFIG_DIR}/panel.env}"

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
    SAN="IP:127.0.0.1"
    if [ -n "${CERT_IP}" ]; then
        SAN="${SAN},IP:${CERT_IP}"
    fi
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "${TLS_KEY}" \
        -out    "${TLS_CERT}" \
        -subj   "/CN=olcrtc-manager" \
        -addext "subjectAltName=${SAN}" \
        2>/dev/null
    echo "[entrypoint] TLS certificate written to ${CONFIG_DIR}"
fi

# Create a minimal default config if none exists
if [ ! -f "${CONFIG_PATH}" ]; then
    echo "[entrypoint] Creating default config at ${CONFIG_PATH}"
    cat > "${CONFIG_PATH}" <<'EOF'
{
  "version": 2,
  "name": "olcrtc-manager",
  "port": 8443,
  "subscription_path": "/subs",
  "refresh": "1h",
  "clients": []
}
EOF
fi

exec /usr/local/bin/olcrtc-manager -config "${CONFIG_PATH}"
