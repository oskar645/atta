# Timeweb Nginx for ATTA Backend

Этот документ описывает внешний доступ к backend ATTA через Nginx reverse proxy на Timeweb.

## Текущая схема

- backend работает через PM2
- backend слушает локальный порт `3000`
- Nginx принимает внешний HTTP на `80`
- Nginx проксирует запросы на `http://127.0.0.1:3000`

## Что должно работать

- `http://5.42.125.179/health`
- `http://5.42.125.179/health/dependencies`

## WebSocket support

В Nginx proxy должны быть headers:

- `Upgrade`
- `Connection`
- `Host`
- `X-Real-IP`
- `X-Forwarded-For`
- `X-Forwarded-Proto`

Это нужно для Socket.IO / realtime-части backend.

## Безопасность

- PostgreSQL наружу не открывается
- Redis наружу не открывается
- MinIO наружу не открывается
- внешний доступ идет только через Nginx на `80`

`docker-compose.server.yml` уже привязывает сервисы только к `127.0.0.1`:

- PostgreSQL: `127.0.0.1:5432`
- Redis: `127.0.0.1:6379`
- MinIO API: `127.0.0.1:9000`
- MinIO Console: `127.0.0.1:9001`

## Временный backend URL

Пока без домена Flutter может использовать:

```text
http://5.42.125.179
```

Для настоящего продакшена нужен HTTPS, например:

```text
https://api.your-domain.ru
```

## Firewall рекомендации

Открывать наружу:

- `22/tcp` SSH
- `80/tcp` HTTP
- `443/tcp` HTTPS на будущее

Не открывать наружу:

- `5432/tcp` PostgreSQL
- `6379/tcp` Redis
- `9000/tcp` MinIO
- `9001/tcp` MinIO console
- `3000/tcp` backend напрямую, если Nginx уже работает
