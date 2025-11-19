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

set +e
./mv2mariadb --force-convert "$@"
status=$?
set -e

cp "${CONFIG_TARGET}" "${CONFIG_SOURCE}"

exit ${status}
