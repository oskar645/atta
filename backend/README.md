# ATTA Backend

Это отдельный backend skeleton для проекта ATTA.

Важно:

- это только начальный backend skeleton;
- Flutter-приложение пока не переключено на него;
- текущая Supabase-логика Flutter не изменяется этим этапом;
- Supabase пока не удален и продолжает оставаться текущим рабочим backend приложения;
- реальные секреты, ключи и токены в репозиторий не добавляются.

## Технологии

- NestJS
- PostgreSQL
- Prisma
- Redis
- Socket.IO
- S3-compatible storage
- JWT auth skeleton

## Структура

```text
backend/
  apps/api/src/
  prisma/
  .env.example
  package.json
  tsconfig.json
```

## Установка зависимостей

```bash
cd backend
npm install
```

## Env переменные

Создайте локальный `.env` на основе `.env.example`:

```bash
cd backend
cp .env.example .env
```

Нужны как минимум:

- `NODE_ENV`
- `PORT`
- `DATABASE_URL`
- `REDIS_URL`
- `JWT_ACCESS_SECRET`
- `JWT_REFRESH_SECRET`
- `ADMIN_PHONE_NUMBERS`
- `S3_ENDPOINT`
- `S3_REGION`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`
- `S3_BUCKET_AVATARS`
- `S3_BUCKET_LISTING_PHOTOS`
- `S3_BUCKET_CHAT_IMAGES`
- `S3_BUCKET_FEED_ADS`
- `SMS_RU_API_ID`
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY_PATH`

## Phone verification через SMS.ru

Для callcheck-верификации телефона backend читает ключ только из env:

```bash
SMS_RU_CALLCHECK_ENABLED=true
SMS_RU_API_ID=your_sms_ru_api_id
```

Куда класть ключ:

- локально: в `backend/.env`
- на сервере: в `backend/.env.production`

Важно:

- реальный `SMS_RU_API_ID` нельзя коммитить;
- на Timeweb сервере должны быть `SMS_RU_CALLCHECK_ENABLED=true` и реальный `SMS_RU_API_ID`;
- если `SMS_RU_CALLCHECK_ENABLED=false`, backend вернет safe error `SMS_RU_CALLCHECK_DISABLED`, и номер для звонка не появится;
- в dev режиме можно оставить fake placeholder и `SMS_RU_CALLCHECK_ENABLED=false`;
- при fake placeholder backend использует безопасный dev flow без реального запроса в SMS.ru.

Endpoints:

```bash
POST /auth/phone/check-registration
POST /auth/phone/start
POST /auth/phone/check
POST /auth/signup-phone
POST /auth/login-phone
POST /auth/reset-password-phone
```

Проверка, зарегистрирован ли номер:

```json
{
  "phone": "89288888645"
}
```

Пример ответа, если пользователь уже существует:

```json
{
  "exists": true,
  "phone": "79288888645",
  "message": "Phone is already registered"
}
```

Пример ответа, если номер свободен:

```json
{
  "exists": false,
  "phone": "79288888645",
  "message": "Phone is available"
}
```

Curl пример:

```bash
curl -X POST http://localhost:3000/auth/phone/check-registration \
  -H "Content-Type: application/json" \
  -d '{"phone":"8 (928) 888-86-45"}'
```

Bootstrap admin по номеру:

```env
ADMIN_PHONE_NUMBERS=79288888645,79306939954
```

Пример регистрации по телефону:

```bash
curl -X POST http://localhost:3000/auth/signup-phone \
  -H "Content-Type: application/json" \
  -d '{
    "phone":"89288888645",
    "password":"12345678",
    "displayName":"Mansur",
    "verificationCheckId":"fake-check-id"
  }'
```

Пример входа по телефону:

```bash
curl -X POST http://localhost:3000/auth/login-phone \
  -H "Content-Type: application/json" \
  -d '{
    "phone":"89288888645",
    "password":"12345678"
  }'
```

Пример сброса пароля по телефону:

```bash
curl -X POST http://localhost:3000/auth/reset-password-phone \
  -H "Content-Type: application/json" \
  -d '{
    "phone":"89288888645",
    "newPassword":"12345678",
    "verificationCheckId":"fake-check-id"
  }'
```

Пример запуска звонка:

```json
{
  "phone": "79288888645",
  "purpose": "signup"
}
```

Пример проверки:

```json
{
  "phone": "79288888645",
  "checkId": "provider-check-id",
  "purpose": "signup"
}
```

## Локальная dev-инфраструктура через Docker Compose

Поднимаются:

- PostgreSQL
- Redis
- MinIO

Команды:

```bash
cd backend
npm run docker:up
```

Остановить:

```bash
cd backend
npm run docker:down
```

## Server-only Docker Compose

Для Timeweb / server используйте:

```bash
cd backend
npm run docker:server:up
```

Остановить:

```bash
cd backend
npm run docker:server:down
```

В `docker-compose.server.yml` PostgreSQL, Redis и MinIO привязаны только к `127.0.0.1`, чтобы не открывать их публично в интернет.

## Production run через PM2

После сборки backend можно запускать постоянно без `npm run dev`:

```bash
cd backend
npm run build
npm run pm2:start
```

Полезные команды:

```bash
npm run pm2:restart
npm run pm2:stop
npm run pm2:logs
```

Что нужно сделать на сервере Timeweb:

1. Открыть `/opt/atta-backend/.env`.
2. Проверить:

```env
SMS_RU_CALLCHECK_ENABLED=true
SMS_RU_API_ID=<реальный ключ>
```

3. Перезапустить backend:

```bash
cd /opt/atta-backend
npm run pm2:restart
```

4. Проверить:

```bash
curl http://127.0.0.1:3000/health
curl http://127.0.0.1:3000/health/dependencies
```

`.env` не коммитится. В `.env.example` оставляем только placeholder.

Выдать admin-права существующему пользователю по номеру:

```bash
npm run admin -- 79288888645
```

Параметры локальной dev-среды:

- PostgreSQL: `localhost:5432`, db `atta_dev`, user `atta`, password `atta_password`
- Redis: `localhost:6379`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`

## Генерация Prisma client

```bash
cd backend
npm run prisma:generate
```

## Проверка Prisma schema

```bash
cd backend
npx prisma validate
```

## Локальная миграция Prisma

```bash
cd backend
npm run prisma:migrate:dev
```

## Server-safe Prisma deploy

Для Timeweb / server используйте только:

```bash
cd backend
npm run prisma:migrate:deploy
```

Важно:

- локальная разработка: `npm run prisma:migrate:dev`
- сервер / Timeweb: `npm run prisma:migrate:deploy`
- на сервере нельзя использовать `prisma migrate dev`

## Prisma Studio

```bash
cd backend
npm run prisma:studio
```

## Локальный запуск backend

```bash
cd backend
npm run dev
```

## Проверка health endpoints

После запуска backend:

```bash
curl http://localhost:3000/health
```

Ответ:

```json
{
  "status": "ok"
}
```

Проверка зависимостей skeleton:

```bash
curl http://localhost:3000/health/dependencies
```

Ответ:

```json
{
  "api": "ok",
  "database": "not_checked_yet",
  "redis": "not_checked_yet",
  "s3": "not_checked_yet"
}
```

## Что уже есть

- health endpoint
- auth module skeleton
- users module skeleton
- phone verification skeleton
  - SMS.ru callcheck start/check endpoints are now wired in backend
- listings skeleton
- storage skeleton
- chats REST skeleton
- Socket.IO gateway skeleton
- presence skeleton
- Prisma schema base

## Что пока не реализовано полностью

- реальная интеграция PostgreSQL
- реальные Prisma services/repositories
- настоящая JWT авторизация
- Argon2/bcrypt production hashing
- реальные Redis operations
- реальная интеграция S3
- реальные SMS.ru call verification flows
- реальные APNs push
- production guards, policies и audit flows

## Важно для проекта

- Flutter UI не подключен к этому backend.
- Supabase-сервисы Flutter не менялись.
- Supabase не удален и не заменен на этом этапе.
- Этот backend создается как отдельная безопасная основа для следующего этапа реализации.
