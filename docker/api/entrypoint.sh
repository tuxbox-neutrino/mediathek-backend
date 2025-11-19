#!/usr/bin/env bash
set -euo pipefail

API_HOME=${API_HOME:-/opt/api}
API_DIST_DIR=${API_DIST_DIR:-/opt/api.dist}
WWW_DIR="${API_HOME}/www"
DATA_DIR="${API_HOME}/data"
LOG_DIR="${API_HOME}/log"
CONFIG_DIR="${API_HOME}/config"
BIN_DIR="${API_HOME}/bin"
BINARY_PATH="${BIN_DIR}/mt-api"
DIST_BIN="${API_DIST_DIR}/bin"

# Ensure Lighttpd/CGI inherit the DB host even when not explicitly provided.
MT_API_DB_HOST=${MT_API_DB_HOST:-mediathek-db}
MT_API_DB_PORT=${MT_API_DB_PORT:-3306}
MT_API_DB_NAME=${MT_API_DB_NAME:-mediathek_1}
export MT_API_DB_HOST MT_API_DB_PORT MT_API_DB_NAME
mkdir -p "${WWW_DIR}" "${DATA_DIR}" "${LOG_DIR}" "${CONFIG_DIR}" "${BIN_DIR}"
chown www-data:www-data "${LOG_DIR}"

# Seed static assets on first run if the target directories are empty.
if [[ -d "${API_DIST_DIR}/www" ]] && [[ ! -f "${WWW_DIR}/mt-api.cgi" ]]; then
  echo "[api-entrypoint] Populating www/ from defaults."
  cp -a "${API_DIST_DIR}/www/." "${WWW_DIR}/"
fi

if [[ -d "${API_DIST_DIR}/data" ]] && [[ ! -e "${DATA_DIR}/template/index.html" ]]; then
  echo "[api-entrypoint] Populating data/ from defaults."
  cp -a "${API_DIST_DIR}/data/." "${DATA_DIR}/"
fi

# ensure password directory exists after seeding
mkdir -p "${DATA_DIR}/.passwd"

if [[ -d "${DIST_BIN}" ]] && [[ ! -f "${BINARY_PATH}" ]]; then
  echo "[api-entrypoint] Installing mt-api binary."
  cp -a "${DIST_BIN}/." "${BIN_DIR}/"
  chmod +x "${BINARY_PATH}"
fi

# Allow local overrides for database credentials.
if [[ -f "${CONFIG_DIR}/sqlpasswd" ]]; then
  cp "${CONFIG_DIR}/sqlpasswd" "${DATA_DIR}/.passwd/sqlpasswd"
elif [[ ! -f "${DATA_DIR}/.passwd/sqlpasswd" ]]; then
  echo "root:example-root" > "${DATA_DIR}/.passwd/sqlpasswd"
fi
chmod 600 "${DATA_DIR}/.passwd/sqlpasswd"
chown www-data:www-data "${DATA_DIR}/.passwd/sqlpasswd"

chown www-data:www-data "${DATA_DIR}" "${DATA_DIR}/.passwd" || true

if [[ -f "${API_DIST_DIR}/VERSION" ]]; then
  build_info=$(cat "${API_DIST_DIR}/VERSION")
else
  build_info="unknown"
fi

echo "[api-entrypoint] mt-api build ${build_info}"
echo "[api-entrypoint] Launching lighttpd on port 8080."
exec /usr/sbin/lighttpd -D -f /etc/lighttpd/lighttpd.conf
