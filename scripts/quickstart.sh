#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="0.2.0"

if [[ "${1:-}" == "--version" ]]; then
  echo "quickstart.sh version ${SCRIPT_VERSION}"
  exit 0
fi

echo "[quickstart] Script version ${SCRIPT_VERSION}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[quickstart] docker is required."
  exit 1
fi

ROOT_DIR="${ROOT_DIR:-$(pwd)}"
CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/config/importer}"
DATA_DIR="${DATA_DIR:-${ROOT_DIR}/data/importer}"
API_CONFIG_DIR="${API_CONFIG_DIR:-${ROOT_DIR}/config/api}"
NETWORK_MODE="${NETWORK_MODE:-bridge}" # bridge | host
NETWORK_NAME="${NETWORK_NAME:-mediathek-net}"
API_PORT="${API_PORT:-18080}"
API_DATA_VOLUME="${API_DATA_VOLUME:-mediathek-backend_mt-api-data}"
API_LOG_VOLUME="${API_LOG_VOLUME:-mediathek-backend_mt-api-log}"
CURRENT_USER=$(id -un)
CURRENT_GROUP=$(id -gn)

mkdir -p "${CONFIG_DIR}" "${DATA_DIR}" "${API_CONFIG_DIR}"

ensure_writable_path() {
  local target="$1" label="$2" probe="$1"
  if [[ ! -e "${probe}" ]]; then
    probe=$(dirname "${probe}")
  fi
  if [[ ! -w "${probe}" ]]; then
    cat <<EOF
[quickstart] ERROR: ${label} (${target}) is not writable by ${CURRENT_USER}.
[quickstart] Fix permissions, e.g.:
[quickstart]   sudo chown -R ${CURRENT_USER}:${CURRENT_GROUP} ${ROOT_DIR}
EOF
    exit 1
  fi
}

ensure_writable_path "${CONFIG_DIR}" "Importer config directory"
ensure_writable_path "${DATA_DIR}" "Importer data directory"
ensure_writable_path "${API_CONFIG_DIR}" "API config directory"

ensure_volume() {
  local name="$1"
  if ! docker volume inspect "${name}" >/dev/null 2>&1; then
    docker volume create "${name}" >/dev/null
  fi
}

ensure_volume "${API_DATA_VOLUME}"
ensure_volume "${API_LOG_VOLUME}"

prompt() {
  local __var="$1" __text="$2" __default="$3" __input
  read -r -p "${__text} [${__default}]: " __input
  if [[ -z "${__input}" ]]; then
    __input="${__default}"
  fi
  printf -v "${__var}" '%s' "${__input}"
}

prompt_secret() {
  local __var="$1" __text="$2" __default="$3" __input
  read -r -s -p "${__text} [${__default}]: " __input
  echo
  if [[ -z "${__input}" ]]; then
    __input="${__default}"
  fi
  printf -v "${__var}" '%s' "${__input}"
}

DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-example-root}"
prompt DB_USER "MariaDB user" "${DB_USER}"
prompt_secret DB_PASS "MariaDB password" "${DB_PASS}"
DB_ROOT_PASS="${DB_ROOT_PASS:-${DB_PASS}}"

if [[ "${DB_USER}" == "root" && "${DB_PASS}" == "example-root" ]]; then
  cat <<'EOF'
[quickstart] WARNING: You chose the default root/example-root credentials.
[quickstart] This is fine for local testing, but DO NOT expose the service
[quickstart] publicly before changing both user and password.
EOF
fi

start_db_default="Y"
read -r -p "Start bundled MariaDB container? [Y/n]: " START_DB
START_DB=${START_DB:-${start_db_default}}

if [[ "${START_DB,,}" =~ ^(y|)$ ]]; then
  DB_HOST="mediathek-db"
else
  prompt DB_HOST "MariaDB host" "${DB_HOST:-localhost}"
fi

API_DB_HOST="${MT_API_DB_HOST:-${DB_HOST}}"

wait_for_db_container() {
  local container="$1" root_pass="$2" timeout="${3:-120}"
  local elapsed=0
  local spinner='|/-\'
  printf "[quickstart] Waiting for MariaDB in container '%s'..." "${container}"
  while (( elapsed < timeout )); do
    if docker exec "${container}" mariadb-admin -uroot -p"${root_pass}" ping >/dev/null 2>&1; then
      printf "\r[quickstart] MariaDB is ready after %ds.%-20s\n" "${elapsed}" ""
      return 0
    fi
    local frame=$(((elapsed/2) % 4))
    printf "\r[quickstart] Waiting for MariaDB %c (elapsed %ds)" "${spinner:frame:1}" "${elapsed}"
    sleep 2
    ((elapsed+=2))
  done
  printf "\n[quickstart] MariaDB did not become ready within %ds.\n" "${timeout}"
  return 1
}

ensure_db_user() {
  local container="$1" user="$2" pass="$3" root_pass="$4"
  if [[ "${user}" == "root" ]]; then
    return 0
  fi
  if ! docker exec -i "${container}" mariadb -uroot -p"${root_pass}" >/dev/null 2>&1 <<SQL
CREATE USER IF NOT EXISTS '${user}'@'%' IDENTIFIED BY '${pass}';
GRANT ALL ON ${VIDEO_DB_NAME}.* TO '${user}'@'%';
GRANT ALL ON ${VIDEO_DB_TEMPLATE_NAME}.* TO '${user}'@'%';
GRANT ALL ON ${VIDEO_DB_TMP1_NAME}.* TO '${user}'@'%';
FLUSH PRIVILEGES;
SQL
  then
    echo "[quickstart] Failed to create MariaDB user '${user}'."
    exit 1
  fi
  echo "[quickstart] Created/updated MariaDB user '${user}'."
}

ensure_config_value() {
  local file="$1" key="$2" value="$3"
  if [[ ! -f "${file}" ]]; then
    echo "${key}=${value}" >> "${file}"
    return
  fi
  if grep -q "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    echo "${key}=${value}" >> "${file}"
  fi
}

get_config_value() {
  local file="$1" key="$2" value
  value=$(grep "^${key}=" "${file}" | tail -n1 | cut -d'=' -f2-)
  echo "${value}"
}

if [[ "${NETWORK_MODE}" == "host" ]]; then
  IMPORTER_NET_ARGS=(--network host)
  API_NET_ARGS=(--network host)
  DB_NET_ARGS=(--network host)
  API_PORT_ARGS=()
else
  docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 || docker network create "${NETWORK_NAME}"
  IMPORTER_NET_ARGS=(--network "${NETWORK_NAME}")
  API_NET_ARGS=(--network "${NETWORK_NAME}")
  DB_NET_ARGS=(--network "${NETWORK_NAME}")
  API_PORT_ARGS=(-p "${API_PORT}:8080")
fi

ensure_writable_path "${CONFIG_DIR}/mv2mariadb.conf" "Importer config file"

if [[ ! -f "${CONFIG_DIR}/mv2mariadb.conf" ]]; then
  cat > "${CONFIG_DIR}/mv2mariadb.conf" <<EOF
aktFileName=Filmliste-akt.xz
diffFileName=Filmliste-diff.xz
downloadServerCount=1
downloadServer_01=https://liste.mediathekview.de/Filmliste-akt.xz
downloadServerConnectFailsMax=3
downloadServerConnectFail_01=0
serverListUrl=https://res.mediathekview.de/akt.xml
serverListRefreshDays=1
mysqlHost=${DB_HOST}
passwordFile=pw_mariadb
videoDb=mediathek_1
videoDbBaseName=mediathek_1
videoDbTemplate=mediathek_1_template
videoDbTmp1=mediathek_1_tmp1
videoDb_TableInfo=channelinfo
videoDb_TableVersion=version
videoDb_TableVideo=video
EOF
  echo "[quickstart] Generated ${CONFIG_DIR}/mv2mariadb.conf"
fi

ensure_config_value "${CONFIG_DIR}/mv2mariadb.conf" "testMode" "false"
ensure_config_value "${CONFIG_DIR}/mv2mariadb.conf" "testLabel" "_TEST"

VIDEO_DB_NAME=$(get_config_value "${CONFIG_DIR}/mv2mariadb.conf" "videoDb")
VIDEO_DB_TEMPLATE_NAME=$(get_config_value "${CONFIG_DIR}/mv2mariadb.conf" "videoDbTemplate")
VIDEO_DB_NAME=${VIDEO_DB_NAME:-mediathek_1}
VIDEO_DB_TEMPLATE_NAME=${VIDEO_DB_TEMPLATE_NAME:-mediathek_1_template}
VIDEO_DB_TMP1_NAME=$(get_config_value "${CONFIG_DIR}/mv2mariadb.conf" "videoDbTmp1")
VIDEO_DB_TMP1_NAME=${VIDEO_DB_TMP1_NAME:-mediathek_1_tmp1}
VIDEO_TABLE_NAME=$(get_config_value "${CONFIG_DIR}/mv2mariadb.conf" "videoDb_TableVideo")
INFO_TABLE_NAME=$(get_config_value "${CONFIG_DIR}/mv2mariadb.conf" "videoDb_TableInfo")
VERSION_TABLE_NAME=$(get_config_value "${CONFIG_DIR}/mv2mariadb.conf" "videoDb_TableVersion")
VIDEO_TABLE_NAME=${VIDEO_TABLE_NAME:-video}
INFO_TABLE_NAME=${INFO_TABLE_NAME:-channelinfo}
VERSION_TABLE_NAME=${VERSION_TABLE_NAME:-version}

ensure_writable_path "${CONFIG_DIR}/pw_mariadb" "Importer password file"
printf '%s:%s\n' "${DB_USER}" "${DB_PASS}" > "${CONFIG_DIR}/pw_mariadb"
chmod 600 "${CONFIG_DIR}/pw_mariadb"
echo "[quickstart] Wrote ${CONFIG_DIR}/pw_mariadb"

ensure_writable_path "${API_CONFIG_DIR}/sqlpasswd" "API password file"
printf '%s:%s\n' "${DB_USER}" "${DB_PASS}" > "${API_CONFIG_DIR}/sqlpasswd"
chmod 600 "${API_CONFIG_DIR}/sqlpasswd"
echo "[quickstart] Wrote ${API_CONFIG_DIR}/sqlpasswd"

docker pull dbt1/mediathek-importer:latest
docker pull dbt1/mt-api-dev:latest

if [[ "${START_DB,,}" =~ ^(y|)$ ]]; then
  docker pull mariadb:11.4
  docker rm -f mediathek-db >/dev/null 2>&1 || true
  docker run -d --name mediathek-db \
    "${DB_NET_ARGS[@]}" \
    -e MARIADB_ROOT_PASSWORD="${DB_ROOT_PASS}" \
    -e MARIADB_DATABASE=mediathek_1 \
    --restart unless-stopped \
    mariadb:11.4 \
    --character-set-server=utf8mb4 \
    --collation-server=utf8mb4_unicode_ci
  echo "[quickstart] Started local MariaDB container 'mediathek-db'"
  DB_HOST="mediathek-db"
  API_DB_HOST="${DB_HOST}"
  sed -i "s/^mysqlHost=.*/mysqlHost=${DB_HOST}/" "${CONFIG_DIR}/mv2mariadb.conf"
  wait_for_db_container "mediathek-db" "${DB_ROOT_PASS}" 180 || exit 1
  ensure_db_user "mediathek-db" "${DB_USER}" "${DB_PASS}" "${DB_ROOT_PASS}"
else
  echo "[quickstart] Expecting MariaDB at host '${DB_HOST}'. Make sure it is reachable before continuing."
fi

echo "[quickstart] Running importer --update (may take a while)..."
update_success=0
for i in {1..5}; do
  if docker run --rm \
      -v "${CONFIG_DIR}:/opt/importer/config" \
      -v "${DATA_DIR}:/opt/importer/bin/dl" \
      "${IMPORTER_NET_ARGS[@]}" \
      dbt1/mediathek-importer --update; then
    update_success=1
    break
  fi
  echo "[quickstart] Importer failed (attempt $i/5). Retrying in 5s..."
  sleep 5
done
if [[ "${update_success}" -ne 1 ]]; then
  echo "[quickstart] Importer --update failed after multiple attempts."
  exit 1
fi

if [[ "${START_DB,,}" =~ ^(y|)$ ]]; then
  docker exec -i mediathek-db mariadb -uroot -p"${DB_ROOT_PASS}" >/dev/null 2>&1 <<SQL
CREATE DATABASE IF NOT EXISTS ${VIDEO_DB_NAME};
CREATE DATABASE IF NOT EXISTS ${VIDEO_DB_TEMPLATE_NAME};
CREATE DATABASE IF NOT EXISTS ${VIDEO_DB_TMP1_NAME};
USE ${VIDEO_DB_NAME};
CREATE TABLE IF NOT EXISTS ${VIDEO_TABLE_NAME} LIKE ${VIDEO_DB_TEMPLATE_NAME}.${VIDEO_TABLE_NAME};
CREATE TABLE IF NOT EXISTS ${INFO_TABLE_NAME} LIKE ${VIDEO_DB_TEMPLATE_NAME}.${INFO_TABLE_NAME};
CREATE TABLE IF NOT EXISTS ${VERSION_TABLE_NAME} LIKE ${VIDEO_DB_TEMPLATE_NAME}.${VERSION_TABLE_NAME};
SQL
  if [[ $? -ne 0 ]]; then
    echo "[quickstart] Failed to sync schema into ${VIDEO_DB_NAME}."
    exit 1
  fi
else
  echo "[quickstart] Ensure database ${VIDEO_DB_NAME} already contains the required tables on ${DB_HOST}."
fi

echo "[quickstart] Seeding database via importer --force-convert (first run)..."
seed_success=0
for i in {1..5}; do
  if docker run --rm \
      -v "${CONFIG_DIR}:/opt/importer/config" \
      -v "${DATA_DIR}:/opt/importer/bin/dl" \
      "${IMPORTER_NET_ARGS[@]}" \
      dbt1/mediathek-importer --force-convert; then
    seed_success=1
    break
  fi
  echo "[quickstart] Importer --force-convert failed (attempt $i/5). Retrying in 30s..."
  sleep 30
done
if [[ "${seed_success}" -ne 1 ]]; then
  echo "[quickstart] Importer --force-convert failed after multiple attempts."
  exit 1
fi

docker rm -f mediathek-importer >/dev/null 2>&1 || true
docker run -d --name mediathek-importer \
  -v "${CONFIG_DIR}:/opt/importer/config" \
  -v "${DATA_DIR}:/opt/importer/bin/dl" \
  "${IMPORTER_NET_ARGS[@]}" \
  --restart unless-stopped \
  dbt1/mediathek-importer --cron-mode 120 --cron-mode-echo

docker rm -f mediathek-api >/dev/null 2>&1 || true
docker run -d --name mediathek-api \
  "${API_NET_ARGS[@]}" \
  "${API_PORT_ARGS[@]:-}" \
  -v "${API_DATA_VOLUME}:/opt/api/data" \
  -v "${API_LOG_VOLUME}:/opt/api/log" \
  -v "${API_CONFIG_DIR}:/opt/api/config" \
  -e MT_API_DB_HOST="${API_DB_HOST}" \
  --restart unless-stopped \
  dbt1/mt-api-dev:latest

echo "[quickstart] Setup complete. Importer + API are running."
if [[ "${NETWORK_MODE}" == "host" ]]; then
  echo "[quickstart] Access the API via http://localhost:8080/mt-api?mode=api&sub=info"
else
  echo "[quickstart] Access the API via http://localhost:${API_PORT}/mt-api?mode=api&sub=info"
fi
