#!/usr/bin/env bash

set -euo pipefail

SERVER_HOST="${SERVER_HOST:-}"
SERVER_USER="${SERVER_USER:-root}"
TARGET_DIR="/opt/atta-backend"
DRY_RUN="${DRY_RUN:-0}"
DELETE_MODE="${DELETE_MODE:-0}"

if [[ -z "$SERVER_HOST" ]]; then
  echo "SERVER_HOST is required. Example: SERVER_HOST=5.42.125.179 ./scripts/deploy-timeweb.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Deploying backend to ${SERVER_USER}@${SERVER_HOST}:${TARGET_DIR}"

RSYNC_ARGS=(
  -avz
  --exclude ".git/" \
  --exclude "node_modules/" \
  --exclude "dist/" \
  --exclude ".env" \
  --exclude ".env.*" \
  --exclude "logs/" \
  --exclude "uploads/" \
  --exclude "storage/" \
  --exclude ".data/" \
  --exclude "npm-debug.log" \
)

if [[ "$DRY_RUN" == "1" ]]; then
  RSYNC_ARGS+=(--dry-run --itemize-changes)
fi

if [[ "$DELETE_MODE" == "1" ]]; then
  RSYNC_ARGS+=(--delete)
else
  echo "DELETE_MODE=0 -> running without --delete"
fi

rsync "${RSYNC_ARGS[@]}" \
  "${BACKEND_DIR}/" "${SERVER_USER}@${SERVER_HOST}:${TARGET_DIR}/"

echo "Backend uploaded successfully."
