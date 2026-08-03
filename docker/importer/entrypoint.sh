#!/usr/bin/env bash
set -euo pipefail

IMPORTER_HOME=${IMPORTER_HOME:-/opt/importer}
BIN_DIR="${IMPORTER_HOME}/bin"
CONFIG_SOURCE="${IMPORTER_HOME}/config/mv2mariadb.conf"
PASSWORD_SOURCE="${IMPORTER_HOME}/config/pw_mariadb"
CONFIG_TARGET="${BIN_DIR}/mv2mariadb.conf"
PASSWORD_TARGET="${BIN_DIR}/pw_mariadb"
WORK_DIR="${BIN_DIR}/dl"

mkdir -p "${WORK_DIR}"

if [[ ! -f "${CONFIG_SOURCE}" ]]; then
  echo "[importer] Missing config file ${CONFIG_SOURCE}."
  echo "[importer] Please copy the template from the upstream repository and adjust the DB settings."
  exit 1
fi

if [[ ! -f "${PASSWORD_SOURCE}" ]]; then
  echo "[importer] Missing password file ${PASSWORD_SOURCE} (format: user:password)."
  exit 1
fi

rm -f "${CONFIG_TARGET}" "${PASSWORD_TARGET}"
cp "${CONFIG_SOURCE}" "${CONFIG_TARGET}"
cp "${PASSWORD_SOURCE}" "${PASSWORD_TARGET}"

export HOME="${IMPORTER_HOME}"
cd "${BIN_DIR}"

# Do not force a conversion here. With --force-convert wired in, every run
# that passes the --cron-mode block rebuilds the whole database including its
# indexes, even when the film list has not changed at all - roughly 90 seconds
# of pure write load per run for no new data. Callers that genuinely want an
# unconditional import pass --force-convert themselves.
set +e
./mv2mariadb "$@"
status=$?
set -e

cp "${CONFIG_TARGET}" "${CONFIG_SOURCE}"

exit ${status}
