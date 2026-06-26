# ATTA Backend Migration Plan

## 1. Общая архитектура backend ATTA

Цель: полностью заменить Supabase на backend в Timeweb Cloud без потери текущего функционала Flutter-приложения и без резкой массовой переписи клиента.

### Базовый стек

- `NestJS` как основной API server и точка orchestration.
- `PostgreSQL` как основная транзакционная база данных.
- `Prisma ORM` как единый data access layer.
- `Redis` для presence, rate limit, временных кодов, TTL-событий, WebSocket fan-out и фоновых задач.
- `Socket.IO` для чатов, статусов доставки/прочтения, online dot и live-уведомлений.
- `Timeweb Cloud Object Storage (S3-compatible)` для фото и медиа.
- `APNs` для iOS push-уведомлений.
- `SMS.ru / call verification` для подтверждения телефона.
- `JWT access/refresh tokens` для auth.

### Логические сервисы

#### API server

Отвечает за REST API для Flutter:

- auth;
- users/profiles;
- listings;
- favorites;
- viewed listings;
- saved searches;
- follows;
- reviews;
- notifications;
- reports;
- support;
- admin;
- feed ads;
- file upload metadata.

#### PostgreSQL

Хранит:

- все бизнес-сущности;
- роли и сессии;
- moderation state;
- события просмотров;
- чат-историю;
- внутренние уведомления;
- аудит действий админов и критичных операций.

#### Redis

Используется для:

- online presence TTL;
- Socket.IO scaling;
- rate limiting;
- throttling phone verification;
- временных locks;
- кэшей вычисляемых счетчиков;
- очередей доставки push и async jobs.

#### S3

Buckets:

- `avatars`
- `listing-photos`
- `chat-images`
- `feed-ads`

#### WebSocket gateway

Отдельный NestJS gateway для:

- auth соединения по JWT;
- подписки на комнаты чатов;
- отправки live message events;
- delivered/read receipts;
- typing;
- online presence;
- live notification events.

#### Push service

Отвечает за:

- хранение APNs device tokens;
- отправку push при offline пользователе;
- доставку push по сообщениям, модерации, подпискам, saved searches;
- дедупликацию и retry.

#### SMS.ru phone verification

Отдельный модуль для:

- запуска call verification;
- проверки статуса подтверждения;
- rate limit на номер/IP/device;
- хранения попыток и результатов;
- создания/входа/сброса пароля после успешного подтверждения.

#### Admin API

Отдельная группа защищенных endpoints:

- dashboard;
- users list;
- moderation;
- reports;
- support;
- feed ads;
- audit logs;
- manual actions over listings/reviews/users.

### Рекомендуемая модульная структура NestJS

```text
backend/
  apps/api/src/
    modules/
      auth/
      users/
      phone-verification/
      listings/
      storage/
      favorites/
      viewed-listings/
      saved-searches/
      follows/
      reviews/
      chats/
      presence/
      notifications/
      reports/
      support/
      admin/
      feed-ads/
      devices/
      audit/
    common/
      guards/
      interceptors/
      pipes/
      dto/
      utils/
```

## 2. PostgreSQL schema

Ниже указана целевая схема. В ней сохранены текущие сущности Supabase и добавлены новые таблицы/поля, которых не хватает для production backend вне Supabase.

### 2.1 `users`

Назначение: основной профиль пользователя.

Поля:

- `id uuid pk`
- `email varchar(255) null unique`
- `phone varchar(32) null unique`
- `phone_verified boolean not null default false`
- `display_name varchar(120) not null default ''`
- `name varchar(120) not null default ''`
- `avatar_url text null`
- `photo_url text null`
- `password_hash text not null`
- `status varchar(32) not null default 'active'`
- `blocked_at timestamptz null`
- `block_reason text null`
- `last_login_at timestamptz null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`
- `deleted_at timestamptz null`

Индексы:

- unique index on `email` where `email is not null`
- unique index on `phone` where `phone is not null`
- index on `status`
- index on `created_at desc`

Связи:

- 1:N с `user_sessions`
- 1:N с `user_devices`
- 1:N с `listings`
- 1:N с `reviews`
- 1:N с `favorites`

Переносится из Supabase:

- `id,email,phone,phone_verified,display_name,name,avatar_url,photo_url,created_at,updated_at`

Новые поля:

- `password_hash`
- `status`
- `blocked_at`
- `block_reason`
- `last_login_at`
- `deleted_at`

### 2.2 `admin_users`

Назначение: административные роли.

Поля:

- `user_id uuid pk references users(id)`
- `is_admin boolean not null default true`
- `role varchar(32) not null default 'admin'`
- `permissions jsonb not null default '{}'`
- `created_at timestamptz not null default now()`
- `created_by uuid null references users(id)`

Индексы:

- index on `role`

Переносится из Supabase:

- `uid -> user_id`
- `is_admin`
- `created_at`

Новые поля:

- `permissions`
- `created_by`

### 2.3 `user_sessions`

Назначение: refresh sessions.

Поля:

- `id uuid pk`
- `user_id uuid not null references users(id) on delete cascade`
- `refresh_token_hash text not null`
- `device_id uuid null`
- `device_name varchar(255) null`
- `ip inet null`
- `user_agent text null`
- `expires_at timestamptz not null`
- `revoked_at timestamptz null`
- `created_at timestamptz not null default now()`

Индексы:

- index on `user_id, created_at desc`
- index on `expires_at`

Новые поля:

- вся таблица новая, заменяет Supabase session handling

### 2.4 `phone_verifications`

Назначение: хранение всех попыток phone verification.

Поля:

- `id uuid pk`
- `phone varchar(32) not null`
- `purpose varchar(32) not null`
- `provider varchar(32) not null default 'sms_ru'`
- `provider_check_id varchar(128) null`
- `provider_status_code varchar(64) null`
- `provider_status_text text null`
- `attempts_count integer not null default 0`
- `max_attempts integer not null default 10`
- `requested_by_ip inet null`
- `requested_by_device_id uuid null`
- `verified_at timestamptz null`
- `expires_at timestamptz not null`
- `created_user_id uuid null references users(id)`
- `metadata jsonb not null default '{}'`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Индексы:

- index on `phone, purpose, created_at desc`
- index on `provider_check_id`
- index on `expires_at`
- partial index on `verified_at is null`

Переносится из Supabase:

- логика `callcheck_start/callcheck_status`

Новые поля:

- вся таблица новая

### 2.5 `user_devices`

Назначение: девайсы и push tokens.

Поля:

- `id uuid pk`
- `user_id uuid not null references users(id) on delete cascade`
- `platform varchar(16) not null`
- `device_token text not null`
- `device_uid varchar(255) null`
- `app_version varchar(64) null`
- `build_number varchar(64) null`
- `locale varchar(16) null`
- `is_active boolean not null default true`
- `last_seen_at timestamptz not null default now()`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Индексы:

- unique index on `device_token`
- index on `user_id, is_active`

Новые поля:

- вся таблица новая

### 2.6 `listings`

Назначение: объявления.

Поля:

- `id uuid pk`
- `owner_id uuid not null references users(id) on delete cascade`
- `owner_email varchar(255) null`
- `owner_name varchar(120) not null default ''`
- `title varchar(255) not null`
- `description text not null default ''`
- `category varchar(120) not null`
- `subcategory varchar(120) not null default ''`
- `price bigint not null default 0`
- `phone varchar(32) not null default ''`
- `phone_hidden boolean not null default false`
- `city varchar(255) not null default ''`
- `address text not null default ''`
- `latitude numeric(10,7) null`
- `longitude numeric(10,7) null`
- `location_json jsonb not null default '{}'`
- `delivery jsonb not null default '{}'`
- `car jsonb null`
- `deal_type varchar(64) null`
- `real_estate_type varchar(64) null`
- `clothes_type varchar(64) null`
- `status varchar(32) not null default 'pending'`
- `rejection_reason text null`
- `moderation_note text null`
- `moderated_by uuid null references users(id)`
- `moderated_at timestamptz null`
- `published_at timestamptz null`
- `archived_at timestamptz null`
- `deleted_at timestamptz null`
- `view_count integer not null default 0`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Статусы:

- `pending`
- `approved`
- `rejected`
- `sold`
- `deleted`
- `archived`

Индексы:

- index on `owner_id, created_at desc`
- index on `status, created_at desc`
- index on `category, status, created_at desc`
- index on `city`
- index on `(latitude, longitude)` через PostGIS или отдельный geo-индекс, если будет включен PostGIS
- GIN index on `location_json`
- GIN/trigram index на `title, description` для поиска

Связи:

- 1:N с `listing_photos`
- 1:N с `listing_views`
- 1:N с `favorites`
- 1:N с `reports`
- 1:N с `reviews`
- 1:N с `chats`

Переносится из Supabase:

- все текущие поля Supabase `listings`, включая `delivery`, `car`, `photo_urls`, `status`, `rejection_reason`, `view_count`

Новые поля:

- `address`
- `latitude`
- `longitude`
- `location_json`
- `moderation_note`
- `moderated_by`
- `moderated_at`
- `published_at`
- `archived_at`
- `deleted_at`

Примечание:

Текущее поле Supabase `photo_urls text[]` рекомендуется заменить на таблицу `listing_photos`. На этапе миграции можно временно сохранить `legacy_photo_urls jsonb null` для back-compat и сверки.

### 2.7 `listing_photos`

Назначение: фото объявлений.

Поля:

- `id uuid pk`
- `listing_id uuid not null references listings(id) on delete cascade`
- `storage_bucket varchar(64) not null default 'listing-photos'`
- `storage_key text not null`
- `public_url text not null`
- `sort_order integer not null default 0`
- `width integer null`
- `height integer null`
- `size_bytes integer null`
- `mime_type varchar(64) null`
- `created_at timestamptz not null default now()`

Индексы:

- index on `listing_id, sort_order`
- unique index on `storage_key`

Переносится из Supabase:

- `photo_urls[]` маппятся в строки

Новые поля:

- вся таблица новая

### 2.8 `listing_views`

Назначение: нормализованная история просмотров.

Поля:

- `id uuid pk`
- `listing_id uuid not null references listings(id) on delete cascade`
- `viewer_user_id uuid null references users(id)`
- `viewer_device_id uuid null`
- `ip inet null`
- `viewed_at timestamptz not null default now()`

Индексы:

- index on `listing_id, viewed_at desc`
- index on `viewer_user_id, viewed_at desc`

Переносится из Supabase:

- только агрегат `view_count`

Новые поля:

- вся таблица новая

### 2.9 `favorites`

Поля:

- `id uuid pk`
- `user_id uuid not null references users(id) on delete cascade`
- `listing_id uuid not null references listings(id) on delete cascade`
- `created_at timestamptz not null default now()`

Индексы:

- unique index on `(user_id, listing_id)`
- index on `user_id, created_at desc`

Переносится из Supabase:

- полностью

### 2.10 `viewed_listings`

Назначение: просмотренные объявления для пользователя.

Поля:

- `id uuid pk`
- `user_id uuid not null references users(id) on delete cascade`
- `listing_id uuid not null references listings(id) on delete cascade`
- `viewed_at timestamptz not null default now()`

Индексы:

- unique index on `(user_id, listing_id)`
- index on `user_id, viewed_at desc`

Новые поля:

- вся таблица новая

### 2.11 `saved_searches`

Поля:

- `id uuid pk`
- `user_id uuid not null references users(id) on delete cascade`
- `title varchar(255) not null default ''`
- `query_key text not null`
- `category varchar(120) not null default 'Все'`
- `search text not null default ''`
- `subcategory varchar(120) not null default 'Все'`
- `location text not null default ''`
- `prefer_location_first boolean not null default false`
- `radius_km integer null`
- `auto_brand varchar(120) not null default ''`
- `auto_model varchar(120) not null default ''`
- `auto_condition varchar(120) not null default ''`
- `auto_mileage_to integer null`
- `only_uncrashed boolean not null default false`
- `alerts_enabled boolean not null default true`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Индексы:

- unique index on `(user_id, query_key)`
- index on `user_id, updated_at desc`

Переносится из Supabase:

- полностью

### 2.12 `user_follows`

Поля:

- `follower_id uuid not null references users(id) on delete cascade`
- `seller_id uuid not null references users(id) on delete cascade`
- `created_at timestamptz not null default now()`

Индексы:

- primary key `(follower_id, seller_id)`
- index on `seller_id, created_at desc`

Переносится из Supabase:

- полностью

### 2.13 `reviews`

Поля:

- `id uuid pk`
- `seller_id uuid not null references users(id) on delete cascade`
- `reviewer_id uuid not null references users(id) on delete cascade`
- `reviewer_name varchar(120) null`
- `listing_id uuid null references listings(id) on delete set null`
- `rating smallint not null`
- `comment text not null default ''`
- `reply_text text null`
- `reply_at timestamptz null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz null`
- `deleted_at timestamptz null`

Индексы:

- index on `seller_id, created_at desc`
- index on `reviewer_id, created_at desc`

Переносится из Supabase:

- полностью

Новые поля:

- `deleted_at`

### 2.14 `chats`

Поля:

- `id uuid pk`
- `listing_id uuid null references listings(id) on delete set null`
- `listing_title varchar(255) not null default ''`
- `buyer_id uuid not null references users(id) on delete cascade`
- `seller_id uuid not null references users(id) on delete cascade`
- `last_message text not null default ''`
- `last_message_type varchar(32) not null default 'text'`
- `last_message_at timestamptz null`
- `unread_for_buyer integer not null default 0`
- `unread_for_seller integer not null default 0`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`
- `deleted_by_buyer_at timestamptz null`
- `deleted_by_seller_at timestamptz null`

Индексы:

- unique index on `(listing_id, buyer_id, seller_id)`
- index on `buyer_id, updated_at desc`
- index on `seller_id, updated_at desc`

Переносится из Supabase:

- текущие поля `chats`

Новые поля:

- `last_message_type`
- `last_message_at`
- soft-delete поля по участникам

### 2.15 `chat_messages`

Поля:

- `id uuid pk`
- `chat_id uuid not null references chats(id) on delete cascade`
- `sender_id uuid not null references users(id) on delete cascade`
- `message_type varchar(32) not null default 'text'`
- `text text not null default ''`
- `image_bucket varchar(64) null`
- `image_key text null`
- `image_url text null`
- `delivered_at timestamptz null`
- `read_at timestamptz null`
- `created_at timestamptz not null default now()`
- `deleted_at timestamptz null`

Индексы:

- index on `chat_id, created_at desc`
- index on `sender_id, created_at desc`

Переносится из Supabase:

- `id,chat_id,sender_id,text,image_url,delivered_at,read_at,created_at`

Новые поля:

- `message_type`
- `image_bucket`
- `image_key`
- `deleted_at`

### 2.16 `message_receipts`

Вариант A: оставить `delivered_at/read_at` в `chat_messages`, как сейчас.

Вариант B: добавить отдельную таблицу, если нужна масштабируемость для групповых чатов в будущем.

Для ATTA сейчас рекомендуется:

- оставить `delivered_at/read_at` в `chat_messages`;
- не усложнять отдельной таблицей на первом этапе.

### 2.17 `user_presence`

Поля:

- `user_id uuid pk references users(id) on delete cascade`
- `is_online boolean not null default false`
- `last_seen timestamptz not null default now()`
- `socket_id varchar(255) null`
- `updated_at timestamptz not null default now()`

Индексы:

- index on `is_online, last_seen desc`

Переносится из Supabase:

- полностью

Новые поля:

- `socket_id`

### 2.18 `user_notifications`

Поля:

- `id uuid pk`
- `user_id uuid null references users(id) on delete cascade`
- `scope varchar(16) not null`
- `type varchar(64) not null default 'generic'`
- `title varchar(255) not null default ''`
- `body text not null default ''`
- `payload jsonb not null default '{}'`
- `is_read boolean not null default false`
- `created_at timestamptz not null default now()`

Индексы:

- index on `user_id, is_read, created_at desc`
- index on `scope, created_at desc`

Переносится из Supabase:

- `id,user_id,scope,title,body,is_read,created_at`

Новые поля:

- `type`
- `payload`

### 2.19 `reports`

Поля:

- `id uuid pk`
- `listing_id uuid null references listings(id) on delete set null`
- `listing_owner_id uuid null references users(id) on delete set null`
- `reporter_id uuid not null references users(id) on delete cascade`
- `reason varchar(255) not null`
- `comment text not null default ''`
- `status varchar(32) not null default 'open'`
- `decision varchar(64) null`
- `admin_uid uuid null references users(id) on delete set null`
- `admin_comment text null`
- `admin_note text null`
- `handled_by uuid null references users(id) on delete set null`
- `handled_at timestamptz null`
- `closed_at timestamptz null`
- `created_at timestamptz not null default now()`

Индексы:

- index on `status, created_at desc`
- index on `listing_owner_id`
- index on `reporter_id`

Переносится из Supabase:

- полностью

### 2.20 `support_tickets`

Поля:

- `id uuid pk`
- `user_id uuid not null references users(id) on delete cascade`
- `name varchar(120) not null default 'Пользователь'`
- `subject varchar(255) not null default 'Обращение в поддержку'`
- `status varchar(32) not null default 'open'`
- `last_message text not null default ''`
- `unread_for_admin boolean not null default false`
- `unread_for_user boolean not null default false`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Индексы:

- index on `user_id`
- index on `status, updated_at desc`
- index on `unread_for_admin`

Переносится из Supabase:

- почти полностью

Новые поля:

- `unread_for_user`

### 2.21 `support_messages`

Поля:

- `id uuid pk`
- `ticket_id uuid not null references support_tickets(id) on delete cascade`
- `sender varchar(16) not null`
- `sender_user_id uuid null references users(id)`
- `text text not null`
- `created_at timestamptz not null default now()`

Индексы:

- index on `ticket_id, created_at desc`

Переносится из Supabase:

- `id,ticket_id,sender,text,created_at`

Новые поля:

- `sender_user_id`

### 2.22 `feed_ads`

Поля:

- `id uuid pk`
- `title varchar(255) not null`
- `image_url text not null`
- `image_bucket varchar(64) not null default 'feed-ads'`
- `image_key text null`
- `target_url text not null default ''`
- `placement varchar(64) not null default 'home'`
- `duration_days integer not null`
- `is_active boolean not null default false`
- `activated_at timestamptz null`
- `expires_at timestamptz null`
- `impression_count bigint not null default 0`
- `click_count bigint not null default 0`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz null`

Индексы:

- index on `placement, is_active`
- index on `expires_at`

Переносится из Supabase:

- полностью

Новые поля:

- `image_bucket`
- `image_key`

### 2.23 `feed_ad_events`

Назначение: детальные события по рекламе.

Поля:

- `id uuid pk`
- `feed_ad_id uuid not null references feed_ads(id) on delete cascade`
- `event_type varchar(32) not null`
- `user_id uuid null references users(id)`
- `device_id uuid null`
- `ip inet null`
- `created_at timestamptz not null default now()`

Индексы:

- index on `feed_ad_id, created_at desc`
- index on `event_type, created_at desc`

Переносится из Supabase:

- только логика `track_feed_ad_event`, не данные

Новые поля:

- вся таблица новая

### 2.24 `audit_logs`

Назначение: аудит критичных действий.

Поля:

- `id uuid pk`
- `actor_user_id uuid null references users(id)`
- `actor_role varchar(32) null`
- `action varchar(128) not null`
- `entity_type varchar(64) not null`
- `entity_id uuid null`
- `old_data jsonb null`
- `new_data jsonb null`
- `metadata jsonb not null default '{}'`
- `ip inet null`
- `created_at timestamptz not null default now()`

Индексы:

- index on `entity_type, entity_id`
- index on `actor_user_id, created_at desc`
- index on `action, created_at desc`

Новые поля:

- вся таблица новая

## 3. Auth flow

### Регистрация по email/password

1. Flutter вызывает `POST /auth/signup/email`.
2. Backend валидирует email и пароль.
3. Пароль хэшируется через `argon2id`.
4. Создается пользователь в `users`.
5. При необходимости создается email verification token.
6. Возвращаются `accessToken`, `refreshToken`, `user`.

### Вход по email/password

1. `POST /auth/login/email`
2. Backend ищет `users.email`.
3. Проверяет `password_hash`.
4. Проверяет, что пользователь не заблокирован и не удален.
5. Создает запись в `user_sessions`.
6. Возвращает JWT pair.

### Регистрация по телефону

1. `POST /phone-verification/start` с `purpose=signup`.
2. Backend создает запись в `phone_verifications`.
3. Запускает `SMS.ru callcheck`.
4. Flutter вызывает `POST /phone-verification/check`.
5. После `verified`, Flutter вызывает `POST /auth/signup/phone`.
6. Backend создает пользователя с `phone_verified=true`.
7. Сразу логинит и отдает JWT pair.

### Подтверждение телефона через звонок/SMS.ru

Backend хранит:

- номер;
- purpose;
- provider check id;
- количество попыток;
- статус;
- TTL.

### Вход по телефону/password

1. `POST /auth/login/phone`
2. Backend ищет пользователя по `phone`.
3. Проверяет пароль.
4. Выдает JWT pair.

### Восстановление пароля

Email:

- `POST /auth/password/forgot/email`
- `POST /auth/password/reset/email`

Телефон:

- `POST /phone-verification/start` с `purpose=reset_password`
- `POST /phone-verification/check`
- `POST /auth/password/reset/phone`

### Logout

- `POST /auth/logout`
- текущий refresh token помечается revoked

### Refresh token

- `POST /auth/refresh`
- backend валидирует refresh token
- rotating refresh tokens рекомендуется включить сразу

### Delete account

`DELETE /auth/account`

Backend:

- проверяет JWT;
- удаляет/обезличивает связанные сущности;
- удаляет фото из S3;
- ревокает сессии;
- soft-delete или hard-delete выбирается политикой проекта.

Для ATTA рекомендуется:

- пользовательские сущности удалять hard-delete там, где это уже соответствует текущему поведению;
- `audit_logs` хранить.

### Admin role check

- access token содержит `role` или `isAdmin`
- сервер все равно делает проверку в БД через guard

## 4. Phone verification

### Flow

#### Start call verification

`POST /phone-verification/start`

Вход:

- `phone`
- `purpose`
- `deviceId`

Действия:

- normalize phone to `+7XXXXXXXXXX`
- rate limit by phone/ip/device
- создать запись в `phone_verifications`
- вызвать SMS.ru
- сохранить `provider_check_id`
- вернуть masked данные для UI

#### Check call verification

`POST /phone-verification/check`

Вход:

- `verificationId` или `provider_check_id`

Действия:

- запросить status у SMS.ru
- обновить запись
- если success, проставить `verified_at`

#### Create user after success

- разрешать `signup/phone` только по `verified_at != null`
- verification должна совпадать по `phone + purpose`

#### Login after success

Для обычного входа повторная верификация не нужна.

#### Reset password by phone

- нужен отдельный verified flow с `purpose=reset_password`

### Защита от повторных попыток

- cooldown между `start` запросами: 30-60 секунд
- лимит стартов на номер: например 5 в час
- лимит проверок статуса: например 20 в час
- блокировка на злоупотребление

### Rate limit

Хранить в Redis:

- `phone:start:<phone>`
- `phone:check:<phone>`
- `phone:ip:<ip>`
- `phone:device:<deviceId>`

### Attempts

В БД хранить:

- `attempts_count`
- `max_attempts`
- время последней попытки

## 5. Listings API

### Endpoints

#### Create listing

- `POST /listings`

Создает объявление в статусе `pending`.

#### Update listing

- `PATCH /listings/:id`

Если пользователь меняет важные поля:

- можно переводить обратно в `pending`

#### Delete listing

- `DELETE /listings/:id`

Логика:

- owner delete -> `archived` или `deleted_by_owner`, если захотите разделить
- admin delete -> `deleted`

Чтобы не ломать текущий UI, пока сохраняем текущие статусы:

- `archived`
- `deleted`

#### Archive listing

- `POST /listings/:id/archive`

#### Publish after moderation

- `POST /admin/listings/:id/approve`

#### Reject listing

- `POST /admin/listings/:id/reject`

Сохраняет:

- `status='rejected'`
- `rejection_reason`
- `moderation_note`
- `moderated_by`

#### Get feed

- `GET /listings/feed`

Поддерживает:

- category
- subcategory
- search
- city/location
- radius
- auto filters
- pagination
- sort

#### Get detail

- `GET /listings/:id`

#### Increment view

- `POST /listings/:id/view`

Логика:

- пишет `listing_views`
- обновляет `listings.view_count`
- дедупликация по user/device за короткое окно рекомендуется

#### Get seller listings

- `GET /users/:id/listings`

Опции:

- `status=approved`
- `status=all` для владельца/админа

#### Get similar listings

- `GET /listings/:id/similar`

#### Search/filter listings

- `GET /listings/search`

Для поиска рекомендуется:

- PostgreSQL full-text + trigram
- отдельный query builder в `ListingsService`

## 6. Storage/S3

### Buckets

- `avatars`
- `listing-photos`
- `chat-images`
- `feed-ads`

### Upload flow

Рекомендуемый вариант:

1. Flutter просит upload intent у backend.
2. Backend возвращает presigned PUT URL или upload policy.
3. Flutter загружает файл напрямую в S3.
4. Flutter подтверждает upload через backend.
5. Backend создает DB record.

Альтернатива на первом этапе:

- upload через backend proxy.

Для ATTA лучше:

- прямой presigned upload, чтобы не перегружать API server.

### Delete flow

- backend удаляет объект из S3
- затем удаляет DB record

### Public URL

Для:

- `avatars`
- `listing-photos`
- `feed-ads`

можно использовать public read URL.

### Signed URL для приватных chat-images

`chat-images` должны быть приватными.

Backend:

- хранит `bucket/key`
- по запросу участника чата выдает signed GET URL на короткий TTL

### Image compression responsibility

Рекомендуемое распределение:

- Flutter сжимает исходник перед upload
- backend дополнительно валидирует MIME, size, extension
- при необходимости в будущем можно добавить async image processing worker

### Migration from Supabase Storage to Timeweb S3

1. Выгрузить список файлов по bucket.
2. Скопировать в S3 с сохранением key structure.
3. Сопоставить URLs в БД.
4. Для chat-images перенести keys без публикации.
5. Проверить random sample вручную.

## 7. Chat/WebSocket

### Socket.IO events

- `connection` auth by JWT
- `chat.join`
- `chat.leave`
- `chat.message.send`
- `chat.message.new`
- `chat.message.delivered`
- `chat.message.read`
- `chat.unread.changed`
- `user.presence.set`
- `user.presence.changed`
- `typing.start`
- `typing.stop`
- `notification.new`

### Connection auth by JWT

Клиент подключается с `accessToken`.

Gateway:

- валидирует JWT;
- сохраняет socket-user mapping в Redis;
- обновляет presence.

### Моментальная доставка

1. Пользователь отправляет `chat.message.send`.
2. Backend валидирует участника чата.
3. Сохраняет сообщение в PostgreSQL.
4. Эмитит `chat.message.new` в комнату чата.
5. Обновляет `last_message`, `updated_at`, unread counters.

### Галочки delivered/read

Delivered:

- когда получатель онлайн и его сокет получил message event

Read:

- когда получатель открыл чат и отправил `chat.message.read`

### Unread counters

Хранятся в `chats.unread_for_buyer/unread_for_seller`.

При необходимости можно потом перейти на derived counters, но сейчас лучше сохранить текущую модель, чтобы не ломать UI.

### Online dot

- online определяется по presence heartbeat и активному сокету
- `user.presence.changed` эмитится подписанным клиентам

### last_seen

- обновляется при disconnect/heartbeat

### Redis TTL

Ключи:

- `presence:user:<userId>`
- TTL 90-120 секунд

Если TTL истек:

- пользователь считается offline

### Push если пользователь offline

Если нет активного сокета:

- создать in-app notification
- отправить APNs push по активным device tokens

## 8. Push notifications

### `user_devices`

Flutter должен регистрировать APNs token через:

- `POST /devices/register`

### APNs token registration

Вход:

- `deviceToken`
- `platform`
- `deviceUid`
- `appVersion`

### Отправка push при новом сообщении

Триггер:

- новый `chat_message`

Условие:

- получатель offline или чат не открыт

### Push по модерации

Отправлять при:

- approve listing
- reject listing
- delete listing by admin

### Push по подпискам

Отправлять подписчикам при новом одобренном объявлении продавца.

### Push по saved searches

Отправлять при появлении нового `approved listing`, подходящего под сохраненный поиск.

### Хранение in-app notification

Каждый push-домен должен параллельно писать `user_notifications`.

## 9. Admin API

### Endpoints

- `GET /admin/dashboard/stats`
- `GET /admin/users`
- `GET /admin/users/:id`
- `POST /admin/users/:id/block`
- `POST /admin/users/:id/unblock`
- `GET /admin/listings/moderation`
- `POST /admin/listings/:id/approve`
- `POST /admin/listings/:id/reject`
- `DELETE /admin/listings/:id`
- `GET /admin/reports`
- `POST /admin/reports/:id/close`
- `GET /admin/support/tickets`
- `POST /admin/support/tickets/:id/reply`
- `GET /admin/feed-ads`
- `POST /admin/feed-ads`
- `PATCH /admin/feed-ads/:id`
- `POST /admin/feed-ads/:id/activate`
- `DELETE /admin/feed-ads/:id`
- `DELETE /admin/reviews/:id`
- `GET /admin/audit-logs`

### Admin dashboard stats

Должен включать:

- total users
- total listings
- approved/pending/sold listings
- open reports
- support tickets
- online users
- feed ads CTR

### Список пользователей с ID

Обязательно возвращать:

- `id`
- `display_name`
- `email`
- `phone`
- `status`
- `created_at`

### Блокировка пользователя

Рекомендуется soft block:

- `users.status='blocked'`
- `blocked_at`
- `block_reason`

### Audit logs

Записывать:

- approve/reject listing
- delete listing
- block/unblock user
- delete review
- reply support
- admin notification actions

## 10. Flutter migration plan

### Цель

Заменить Supabase постепенно, не ломая UI и текущие экраны.

### Шаги

#### 1. Создать новый `ApiClient`

Функции:

- base URL
- auth headers
- refresh handling
- retry policy
- error mapping

#### 2. Создать API-слои

- `AuthApi`
- `UsersApi`
- `ListingsApi`
- `StorageApi`
- `ChatApi`
- `AdminApi`
- `NotificationsApi`
- `SupportApi`
- `ReviewsApi`

#### 3. Ввести feature flags

Например:

- `useNewAuthBackend`
- `useNewListingsBackend`
- `useNewChatBackend`
- `useNewAdminBackend`

#### 4. Не ломать UI

Сначала менять data source под сервисами, а не виджеты.

#### 5. Сохранить skeleton/loading

Текущие экраны завязаны на:

- `FutureBuilder`
- `StreamBuilder`
- `CircularProgressIndicator`

Новый backend должен отдавать данные с аналогичным UX:

- быстрый initial load;
- pagination;
- live updates там, где они есть сейчас.

#### 6. Сохранить текущие экраны

Не менять layout, только адаптировать сервисный слой:

- auth services
- listings services
- chat services
- notifications services
- admin services

## 11. Data migration

### Export Supabase PostgreSQL

- сделать dump schema + data
- отдельно выгрузить storage metadata

### Import to Timeweb PostgreSQL

- поднять новую схему Prisma
- выполнить import через staging
- прогнать проверочные SQL

### Mapping auth users

Так как вне Supabase не будет `auth.users`, нужно:

- использовать текущий `public.users.id` как canonical user id;
- перенести email/phone/profile;
- пароли Supabase напрямую, скорее всего, не экспортируются пригодно для прямого использования.

Практическое решение:

- для email пользователей возможна forced password reset;
- для phone users можно также заставить reset через phone verification;
- если удастся мигрировать hashes безопасно и совместимо, это нужно оценить отдельно, но не считать гарантированным.

### Migration users

Перенести:

- users
- admin_users

### Migration listings

Перенести:

- listings
- photo urls -> listing_photos
- moderation statuses

### Migration photos

Перенести buckets:

- avatars
- listing-photos
- chat_images
- feed-ads

### Migration chats

Перенести:

- chats
- chat_messages
- delivered/read timestamps
- unread counters

### Migration reviews

Перенести полностью.

### Migration favorites

Перенести:

- favorites
- saved_searches
- user_follows

### Migration admin roles

Перенести:

- admin_users

### Что нужно проверить вручную

- соответствие user IDs
- соответствие seller_id / reviewer_id / owner_id
- правильность signed URLs для chat images
- unread counters после миграции
- view_count
- moderation statuses
- reject reasons
- support threads
- reports decisions
- feed ad image links

## 12. Security

### JWT

- access token short TTL: 15-30 минут
- refresh token long TTL: 30-90 дней
- rotating refresh tokens

### Password hashing

- `argon2id`

### Rate limit

Применять к:

- login
- signup
- phone registration check
- refresh
- phone verification start/check
- reset password
- admin endpoints
- upload init

### Validation

- `class-validator` / `zod`
- DTO validation на всех endpoints

### Admin guards

- JWT auth guard
- roles/admin guard
- permission guard для чувствительных действий

### File upload validation

- whitelist MIME
- size limit
- ext validation
- virus scan опционально на следующем этапе

### SQL indexes

Все hot-path таблицы должны иметь индексы:

- listings
- chats
- chat_messages
- notifications
- reports
- support
- feed_ad_events

### CORS

Ограничить по доменам окружений:

- dev
- staging
- production

### Env secrets

Вынести из кода:

- DB URL
- Redis URL
- JWT secrets
- APNs key/cert
- SMS.ru API key
- S3 credentials
- Yandex API key

### Backups

- daily PostgreSQL backups
- point-in-time recovery, если доступно
- S3 lifecycle/versioning по возможности

### Logs

- structured logs
- request ids
- security events
- admin actions
- failed verification/login attempts

## 13. Первый backend milestone

### Milestone 1

- создать backend skeleton
- env config
- database connection
- Prisma schema
- auth module
- users module
- phone verification module

### Milestone 2

- listings
- storage
- favorites
- views

### Milestone 3

- chats
- WebSocket
- presence
- push

### Milestone 4

- admin
- moderation
- reports
- support

### Milestone 5

- migration
- TestFlight
- full cutover from Supabase

## Рекомендации по порядку cutover

1. Сначала поднять новый backend и staging БД.
2. Подключить новый auth и users API за feature flag.
3. Затем перевести listings и storage.
4. После этого перевести favorites, follows, saved searches, reviews.
5. Затем перевести chats/presence/notifications/push.
6. В последнюю очередь перевести admin, reports, support и выполнить production migration.

## Открытые технические решения, которые нужно зафиксировать перед реализацией

- будет ли миграция старых password hashes возможна или нужен forced reset;
- включать ли PostGIS сразу или начать с `latitude/longitude` без geo extensions;
- использовать ли direct-to-S3 upload сразу или временно backend proxy;
- делать ли hard-delete аккаунта полностью, как сейчас, или частично soft-delete;
- нужен ли отдельный worker process для push и image jobs уже в Milestone 1.

## Результат

Этот документ является технической спецификацией первого этапа миграции backend ATTA с Supabase на Timeweb Cloud и должен использоваться как основной план для последующего создания backend skeleton, Prisma schema, модулей NestJS и стратегии миграции данных.

ГОТОВО К СОЗДАНИЮ BACKEND SKELETON
