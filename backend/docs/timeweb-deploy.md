# Timeweb Cloud Deploy for ATTA Backend

Этот документ описывает подготовку и загрузку только backend части проекта ATTA на Timeweb Cloud. Flutter, `lib/`, `ios/`, `android/` и Supabase-код не трогаются.

## A. Как зайти на сервер

```bash
ssh root@5.42.125.179
```

## B. Как установить Docker

```bash
apt update && apt upgrade -y
apt install -y curl git ca-certificates gnupg
curl -fsSL https://get.docker.com | sh
docker --version
docker compose version
```

## C. Как установить Node.js 20

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
node -v
npm -v
```

## D. Как загрузить backend с Mac

На Mac:

```bash
cd backend
SERVER_HOST=5.42.125.179 ./scripts/deploy-timeweb.sh
```

Что делает скрипт:

- отправляет backend через `rsync`
- копирует в `/opt/atta-backend`
- не отправляет `.env`
- не отправляет `node_modules`
- не отправляет `dist`
- не отправляет `.git`

## E. Как на сервере запустить backend

На сервере:

```bash
cd /opt/atta-backend
cp .env.example .env
nano .env
npm install
npm run docker:up
npm run prisma:migrate:deploy
npm run build
npm run dev
```

Для локальной разработки:

```bash
npm run prisma:migrate:dev
```

Для Timeweb / server:

```bash
npm run prisma:migrate:deploy
```

На сервере не использовать:

```bash
prisma migrate dev
```

Для постоянного запуска backend на сервере используйте PM2 и `docker-compose.server.yml`.
Подробный production-run описан в [timeweb-production-run.md](./timeweb-production-run.md).

## F. Как проверить

```bash
curl http://localhost:3000/health
```

Ожидаемый ответ:

```json
{"status":"ok"}
```

## Предупреждение про SMS.ru

Важно:

- В `SMS_RU_API_ID` нельзя вставлять полную ссылку.
- Нужно вставлять только сам `api_id`.
- Реальный ключ нельзя коммитить.

Неправильно:

```env
SMS_RU_API_ID=https://sms.ru/callcheck/add?api_id=...&phone=...&json=1
```

Правильно:

```env
SMS_RU_API_ID=ТОЛЬКО_API_ID_ИЗ_SMS_RU
```

Для admin bootstrap по номеру добавьте:

```env
ADMIN_PHONE_NUMBERS=79288888645,79306939954
```

Выдать admin-права существующему пользователю можно так:

```bash
cd /opt/atta-backend
npm run admin -- 79288888645
```

На сервере Timeweb для рабочего phone registration flow должно быть:

```env
SMS_RU_CALLCHECK_ENABLED=true
SMS_RU_API_ID=<реальный ключ>
```

Если `SMS_RU_CALLCHECK_ENABLED=false`, backend не сможет получить номер для звонка от SMS.ru, и Flutter покажет безопасную ошибку без technical details.
