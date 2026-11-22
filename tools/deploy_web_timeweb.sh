#!/usr/bin/env bash

set -euo pipefail

SERVER_HOST="${SERVER_HOST:-5.42.125.179}"
SERVER_USER="${SERVER_USER:-root}"
SERVER_PORT="${SERVER_PORT:-22}"
REMOTE_ROOT="${REMOTE_ROOT:-/var/www/atta-web}"
RELEASE_ID="$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_RELEASE="${REMOTE_ROOT}/releases/${RELEASE_ID}"
REMOTE_TARGET="${SERVER_USER}@${SERVER_HOST}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SSH_ARGS=(
  -p "${SERVER_PORT}"
  -o BatchMode=yes
  -o ConnectTimeout=20
)
RSYNC_SSH="ssh -p ${SERVER_PORT} -o BatchMode=yes -o ConnectTimeout=20"

cd "${PROJECT_DIR}"

echo "[1/5] Building Flutter Web..."
flutter build web --release --no-version-check

echo "[2/5] Generating web static files..."
node tools/generate_web_static.mjs

test -s build/web/index.html
test -s build/web/main.dart.js

echo "[3/5] Checking SSH access to ${REMOTE_TARGET}:${SERVER_PORT}..."
ssh "${SSH_ARGS[@]}" "${REMOTE_TARGET}" \
  "mkdir -p '${REMOTE_ROOT}/releases' '${REMOTE_ROOT}/backups' '${REMOTE_RELEASE}'"

echo "[4/5] Uploading release ${RELEASE_ID}..."
rsync -az --checksum \
  -e "${RSYNC_SSH}" \
  build/web/ "${REMOTE_TARGET}:${REMOTE_RELEASE}/"

echo "[5/5] Activating release..."
ssh "${SSH_ARGS[@]}" "${REMOTE_TARGET}" \
  bash -s -- "${REMOTE_ROOT}" "${REMOTE_RELEASE}" "${RELEASE_ID}" <<'REMOTE_SCRIPT'
set -euo pipefail

remote_root="$1"
remote_release="$2"
release_id="$3"
current="${remote_root}/current"
next_link="${remote_root}/.current-${release_id}"
backup="${remote_root}/backups/current-${release_id}"

test -s "${remote_release}/index.html"
test -s "${remote_release}/main.dart.js"

rm -f "${next_link}"
ln -s "${remote_release}" "${next_link}"

if [[ -d "${current}" && ! -L "${current}" ]]; then
  mv "${current}" "${backup}"
  if ! mv -Tf "${next_link}" "${current}"; then
    mv "${backup}" "${current}"
    exit 1
  fi
else
  mv -Tf "${next_link}" "${current}"
fi

test -s "${current}/index.html"
test -s "${current}/main.dart.js"
echo "Active web release: ${release_id}"
REMOTE_SCRIPT

echo "Web deploy completed: https://attamarket.online"
