# ATTA Backend API Response Contracts

Этот документ фиксирует JSON-контракты backend для будущего Flutter cutover. Ответы ориентированы на совместимость с текущими Supabase rows и Flutter models.

## General Rules

- Используем `snake_case`.
- Даты всегда в ISO-8601 UTC string.
- `id` всегда строка UUID.
- Пустые коллекции отдаются как `[]`.
- Пустые json-поля отдаются как `{}`.

## Auth

### `POST /auth/login`

```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "phone": null,
    "phone_verified": false,
    "display_name": "ATTA User",
    "name": "ATTA User",
    "avatar_url": null,
    "photo_url": null,
    "status": "active",
    "blocked_at": null,
    "block_reason": null,
    "last_login_at": "2026-06-12T10:00:00.000Z",
    "created_at": "2026-06-01T10:00:00.000Z",
    "updated_at": "2026-06-12T10:00:00.000Z",
    "deleted_at": null
  },
  "auth": {
    "access_token": "jwt",
    "refresh_token": "jwt",
    "token_type": "Bearer",
    "expires_in": 900,
    "user_id": "uuid",
    "session_id": "uuid"
  },
  "admin_profile": null
}
```

### `POST /auth/signup`

Тот же shape, что у `login`.

### `GET /auth/me`

```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "phone": "+79990000000",
    "phone_verified": false,
    "display_name": "ATTA User",
    "name": "ATTA User",
    "avatar_url": "https://cdn.example/avatar.jpg",
    "photo_url": "https://cdn.example/avatar.jpg",
    "status": "active",
    "blocked_at": null,
    "block_reason": null,
    "last_login_at": "2026-06-12T10:00:00.000Z",
    "created_at": "2026-06-01T10:00:00.000Z",
    "updated_at": "2026-06-12T10:00:00.000Z",
    "deleted_at": null
  },
  "admin_profile": null
}
```

### `POST /auth/refresh`

Тот же shape, что у `login`, но с новым `auth`.

### `POST /auth/logout`

```json
{
  "revoked": true
}
```

### `DELETE /auth/account`

```json
{
  "deleted": true,
  "user_id": "uuid"
}
```

## Users

### Current profile

`GET /users/me`

Тот же shape, что `GET /auth/me`.

### Seller profile

`GET /users/public/:id`

```json
{
  "user": {
    "id": "uuid",
    "display_name": "Seller",
    "name": "Seller",
    "avatar_url": "https://cdn.example/avatar.jpg",
    "photo_url": "https://cdn.example/avatar.jpg",
    "phone_verified": true,
    "status": "active",
    "last_login_at": "2026-06-12T10:00:00.000Z",
    "created_at": "2026-06-01T10:00:00.000Z",
    "updated_at": "2026-06-12T10:00:00.000Z"
  }
}
```

### Users list for admin

`GET /users/admin/list`

```json
{
  "items": [
    {
      "id": "uuid",
      "email": "user@example.com",
      "phone": null,
      "phone_verified": false,
      "display_name": "ATTA User",
      "name": "ATTA User",
      "avatar_url": null,
      "photo_url": null,
      "status": "active",
      "blocked_at": null,
      "block_reason": null,
      "last_login_at": null,
      "created_at": "2026-06-01T10:00:00.000Z",
      "updated_at": "2026-06-12T10:00:00.000Z",
      "deleted_at": null,
      "admin_profile": null
    }
  ]
}
```

## Listings

### Feed

`GET /listings`

```json
{
  "items": [
    {
      "id": "uuid",
      "owner_id": "uuid",
      "owner_email": "seller@example.com",
      "owner_name": "Seller",
      "title": "iPhone",
      "description": "Like new",
      "category": "Электроника",
      "subcategory": "Телефоны",
      "price": 50000,
      "phone": "+79990000000",
      "phone_hidden": false,
      "city": "Грозный",
      "address": "",
      "location": {},
      "location_json": {},
      "delivery": {},
      "car": null,
      "deal_type": null,
      "real_estate_type": null,
      "clothes_type": null,
      "photo_urls": [
        "https://cdn.example/listing-1.jpg"
      ],
      "view_count": 10,
      "status": "approved",
      "rejection_reason": "",
      "moderation_note": null,
      "moderated_by": null,
      "moderated_at": null,
      "published_at": "2026-06-12T10:00:00.000Z",
      "archived_at": null,
      "deleted_at": null,
      "created_at": "2026-06-12T09:00:00.000Z",
      "updated_at": "2026-06-12T10:00:00.000Z"
    }
  ],
  "allowed_statuses": [
    "pending",
    "approved",
    "rejected",
    "sold",
    "deleted",
    "archived"
  ]
}
```

### Listing detail

`GET /listings/:id`

```json
{
  "listing": {
    "id": "uuid",
    "owner_id": "uuid",
    "owner_email": "seller@example.com",
    "owner_name": "Seller",
    "title": "iPhone",
    "description": "Like new",
    "category": "Электроника",
    "subcategory": "Телефоны",
    "price": 50000,
    "phone": "+79990000000",
    "phone_hidden": false,
    "city": "Грозный",
    "address": "",
    "location": {},
    "location_json": {},
    "delivery": {},
    "car": null,
    "deal_type": null,
    "real_estate_type": null,
    "clothes_type": null,
    "photo_urls": [],
    "view_count": 10,
    "status": "approved",
    "rejection_reason": "",
    "moderation_note": null,
    "moderated_by": null,
    "moderated_at": null,
    "published_at": "2026-06-12T10:00:00.000Z",
    "archived_at": null,
    "deleted_at": null,
    "created_at": "2026-06-12T09:00:00.000Z",
    "updated_at": "2026-06-12T10:00:00.000Z"
  }
}
```

### Create

`POST /listings`

```json
{
  "listing": {
    "id": "uuid",
    "owner_id": "uuid",
    "owner_email": "seller@example.com",
    "owner_name": "Seller",
    "title": "New listing",
    "description": "",
    "category": "Все",
    "subcategory": "",
    "price": 0,
    "phone": "",
    "phone_hidden": false,
    "city": "",
    "address": "",
    "location": {},
    "location_json": {},
    "delivery": {},
    "car": null,
    "deal_type": null,
    "real_estate_type": null,
    "clothes_type": null,
    "photo_urls": [],
    "view_count": 0,
    "status": "pending",
    "rejection_reason": "",
    "moderation_note": null,
    "moderated_by": null,
    "moderated_at": null,
    "published_at": null,
    "archived_at": null,
    "deleted_at": null,
    "created_at": "2026-06-12T10:00:00.000Z",
    "updated_at": "2026-06-12T10:00:00.000Z"
  },
  "allowed_statuses": [
    "pending",
    "approved",
    "rejected",
    "sold",
    "deleted",
    "archived"
  ]
}
```

### Update

`PATCH /listings/:id`

Response shape: тот же, что `listing detail`.

### Archive

`POST /listings/:id/archive`

```json
{
  "listing": {
    "id": "uuid",
    "status": "archived"
  },
  "status_after_archive": "archived"
}
```

### Delete

`DELETE /listings/:id`

```json
{
  "listing": {
    "id": "uuid",
    "status": "deleted"
  },
  "status_after_delete": "deleted"
}
```

### Moderation

Целевой shape для будущего admin moderation:

```json
{
  "listing": {
    "id": "uuid",
    "status": "approved",
    "rejection_reason": "",
    "moderation_note": null,
    "moderated_by": "uuid",
    "moderated_at": "2026-06-12T10:00:00.000Z"
  }
}
```

### Similar listings

```json
{
  "items": [
    {
      "id": "uuid",
      "category": "Электроника",
      "status": "approved",
      "photo_urls": []
    }
  ]
}
```

### Views

`POST /listings/:id/views`

```json
{
  "listing_id": "uuid",
  "view_count": 11
}
```

## Storage

### Upload listing photo

`POST /storage/listing-photo/upload`

```json
{
  "bucket": "atta-prod-listing-photos",
  "bucket_alias": "listing-photos",
  "key": "listing-photos/1718181818-photo.jpg",
  "upload_url": "https://s3.example/bucket/key?signed=placeholder",
  "public_url": "https://s3.example/bucket/key",
  "content_type": "image/jpeg",
  "expires_in": 900,
  "provider": "timeweb-s3-placeholder"
}
```

### Upload avatar

`POST /storage/avatar/upload`

Тот же shape, но с `bucket_alias: "avatars"`.

### Upload chat image

`POST /storage/chat-image/upload`

Тот же shape, но с `bucket_alias: "chat-images"`.

### Delete file

`DELETE /storage/object`

```json
{
  "bucket": "atta-prod-listing-photos",
  "bucket_alias": "listing-photos",
  "key": "listing-photos/1718181818-photo.jpg",
  "deleted": false,
  "provider": "timeweb-s3-placeholder",
  "request_id": "uuid"
}
```

## Favorites

### Add

`POST /favorites`

```json
{
  "item": {
    "id": "uuid",
    "user_id": "uuid",
    "listing_id": "uuid",
    "created_at": "2026-06-12T10:00:00.000Z"
  }
}
```

### Remove

`DELETE /favorites/:listingId`

```json
{
  "deleted": true,
  "listing_id": "uuid"
}
```

### List

`GET /favorites`

```json
{
  "items": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "listing_id": "uuid",
      "created_at": "2026-06-12T10:00:00.000Z"
    }
  ],
  "favorite_ids": [
    "uuid"
  ]
}
```

## Chats

Целевой contract для будущей реализации.

### List chats

```json
{
  "items": [
    {
      "id": "uuid",
      "listing_id": "uuid",
      "listing_title": "iPhone",
      "buyer_id": "uuid",
      "seller_id": "uuid",
      "last_message": "Здравствуйте",
      "updated_at": "2026-06-12T10:00:00.000Z",
      "unread_for_buyer": 0,
      "unread_for_seller": 1
    }
  ]
}
```

### List messages

```json
{
  "items": [
    {
      "id": "uuid",
      "chat_id": "uuid",
      "sender_id": "uuid",
      "text": "Здравствуйте",
      "image_url": null,
      "created_at": "2026-06-12T10:00:00.000Z",
      "delivered_at": "2026-06-12T10:00:01.000Z",
      "read_at": null
    }
  ]
}
```

### Send message

```json
{
  "message": {
    "id": "uuid",
    "chat_id": "uuid",
    "sender_id": "uuid",
    "text": "Здравствуйте",
    "image_url": null,
    "created_at": "2026-06-12T10:00:00.000Z",
    "delivered_at": null,
    "read_at": null
  }
}
```

### Mark delivered

```json
{
  "updated": true,
  "chat_id": "uuid"
}
```

### Mark read

```json
{
  "updated": true,
  "chat_id": "uuid"
}
```

## Presence

### Online

```json
{
  "user_id": "uuid",
  "is_online": true,
  "last_seen": "2026-06-12T10:00:00.000Z"
}
```

### Offline

```json
{
  "user_id": "uuid",
  "is_online": false,
  "last_seen": "2026-06-12T10:00:00.000Z"
}
```

### Last seen

```json
{
  "user_id": "uuid",
  "is_online": false,
  "last_seen": "2026-06-12T09:59:00.000Z",
  "updated_at": "2026-06-12T10:00:00.000Z"
}
```

## Notifications

### List

```json
{
  "items": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "scope": "personal",
      "type": "generic",
      "title": "Заголовок",
      "body": "Текст",
      "payload": {},
      "is_read": false,
      "created_at": "2026-06-12T10:00:00.000Z"
    }
  ]
}
```

### Read

```json
{
  "updated": true,
  "notification_id": "uuid"
}
```

### Push placeholder

```json
{
  "queued": true,
  "provider": "apns-placeholder"
}
```

## Admin

### Dashboard

```json
{
  "pending_moderation_count": 0,
  "open_reports_count": 0,
  "unread_support_count": 0,
  "needs_attention": false
}
```

### Users list with ID

`GET /users/admin/list`

Response shape: см. раздел `Users list for admin`.

### Moderation list

```json
{
  "items": [
    {
      "id": "uuid",
      "status": "pending",
      "owner_id": "uuid",
      "title": "Объявление"
    }
  ]
}
```

### Approve

```json
{
  "listing": {
    "id": "uuid",
    "status": "approved",
    "moderated_by": "uuid",
    "moderated_at": "2026-06-12T10:00:00.000Z"
  }
}
```

### Reject

```json
{
  "listing": {
    "id": "uuid",
    "status": "rejected",
    "rejection_reason": "Причина",
    "moderated_by": "uuid",
    "moderated_at": "2026-06-12T10:00:00.000Z"
  }
}
```

### Reports

```json
{
  "items": [
    {
      "id": "uuid",
      "listing_id": "uuid",
      "listing_owner_id": "uuid",
      "reporter_id": "uuid",
      "reason": "spam",
      "comment": "Комментарий",
      "status": "open",
      "decision": null,
      "admin_uid": null,
      "admin_comment": null,
      "admin_note": null,
      "handled_by": null,
      "handled_at": null,
      "closed_at": null,
      "created_at": "2026-06-12T10:00:00.000Z"
    }
  ]
}
```

### Support

```json
{
  "items": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "name": "Пользователь",
      "subject": "Обращение в поддержку",
      "status": "open",
      "last_message": "Здравствуйте",
      "unread_for_admin": true,
      "unread_for_user": false,
      "created_at": "2026-06-12T10:00:00.000Z",
      "updated_at": "2026-06-12T10:05:00.000Z"
    }
  ]
}
```
