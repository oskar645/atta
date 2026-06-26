# Timeweb Production Run for ATTA Backend

Этот документ описывает постоянный запуск backend на Timeweb через PM2 без `npm run dev`.

## Команды

```bash
cd /opt/atta-backend
npm install
npm run docker:server:up
npm run prisma:migrate:deploy
npm run build
npm install -g pm2
npm run pm2:start
pm2 save
pm2 startup
```

## Проверка

```bash
curl http://localhost:3000/health
curl http://localhost:3000/health/dependencies
```

Ожидаемые ответы:

```json
{"status":"ok"}
```

```json
{"api":"ok","database":"ok","redis":"ok","s3":"not_checked_yet"}
```

## Что делает PM2

- запускает backend как `atta-backend`
- использует production entrypoint `dist/main.js`
- читает `.env`
- перезапускает приложение при падении
- пишет логи в `backend/logs/`

## Firewall рекомендации

Наружу сейчас нужны только:

- `22` для SSH
- `3000` временно для проверки API
- позже `80/443` для Nginx и SSL

Нельзя открывать публично:

- `5432` PostgreSQL
- `6379` Redis

В `docker-compose.server.yml` PostgreSQL, Redis и MinIO привязаны только к `127.0.0.1`.
