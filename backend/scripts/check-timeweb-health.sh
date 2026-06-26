#!/usr/bin/env bash

set -euo pipefail

SERVER_HOST="${SERVER_HOST:-5.42.125.179}"
SERVER_USER="${SERVER_USER:-root}"

echo "== Local health via server =="
ssh "${SERVER_USER}@${SERVER_HOST}" 'curl -s http://localhost:3000/health && echo && curl -s http://localhost:3000/health/dependencies'

echo
echo "== Public health =="
curl -s "http://${SERVER_HOST}/health"
echo
curl -s "http://${SERVER_HOST}/health/dependencies"
echo

echo "== PM2 status =="
ssh "${SERVER_USER}@${SERVER_HOST}" 'pm2 status atta-backend'

echo
echo "== Docker containers =="
ssh "${SERVER_USER}@${SERVER_HOST}" 'docker ps --format "{{.Names}} {{.Status}} {{.Ports}}"'
