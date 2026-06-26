# ATTA Flutter Supabase Compatibility Map

Этот документ нужен для поэтапного ухода от Supabase к backend на Timeweb Cloud без резкого cutover. Главный принцип: новый backend должен отдавать Flutter почти те же структуры, которые сейчас приходят из Supabase rows / auth session / storage public URLs.

Важно:

- Flutter UI не меняется на этом этапе.
- Supabase-код Flutter не удаляется.
- Переключение должно идти по сервисам, а не одним большим релизом.
- Для максимальной совместимости backend должен отдавать `snake_case` поля там, где Flutter сейчас читает Supabase rows напрямую.

## Migration Rules

- Не менять названия полей вроде `display_name`, `avatar_url`, `photo_urls`, `view_count`, `unread_for_buyer`, `is_read`.
- Не менять типы значений: даты строками ISO-8601, списки фото как массив строк, json-поля как plain JSON object.
- Не скрывать `id` у пользователей, объявлений, чатов, сообщений, тикетов и уведомлений.
- Не переводить response в camelCase.
- Не ломать поведение пустых значений: вместо отсутствия полей лучше отдавать пустую строку, `null`, `[]` или `{}` так же, как это делает текущий Flutter-код.
- Для realtime-замены предусмотреть WebSocket events с payload, совпадающим по shape с текущими Supabase rows.

## Service Map

### `auth_service.dart`

Текущий Supabase usage:

- `onAuthStateChange`
- `currentUser`
- `signIn(email, password)`
- `signUp(email, password, displayName, phone)`
- `signOut()`
- `updateAuthMetadata(displayName, photoUrl)`
- `updateProfile(displayName, photoUrl)` как alias

Flutter ожидает:

- auth user с `uid`, `email`
- metadata-поля `display_name`, `name`, `avatar_url`, `photo_url`, `picture`
- возможность восстановить текущего пользователя после refresh session

REST replacement:

- `POST /auth/login`
- `POST /auth/signup`
- `GET /auth/me`
- `POST /auth/refresh`
- `POST /auth/logout`
- `DELETE /auth/account`
- `PATCH /users/me` для замены `updateAuthMetadata` / `updateProfile`

WebSocket replacement:

- `auth.session.updated`
- `auth.user.updated`

Поля, которые должны совпадать:

- `user.id`
- `user.email`
- `user.display_name`
- `user.name`
- `user.avatar_url`
- `user.photo_url`
- `auth.access_token`
- `auth.refresh_token`

Нельзя менять:

- семантику `current user`
- работу через access + refresh tokens
- наличие `display_name` и `avatar_url` в user payload

### `phone_auth_backend_service.dart`

Текущий Supabase usage:

- HTTP call в Edge Function `functions/v1/phone-auth`
- action `check_registration`
- action `login`
- action `signup`
- action `reset_password`
- action `link_email`
- action `delete_account`
- после успеха Flutter ожидает `refresh_token` или `session.refresh_token`

Flutter ожидает:

- `registered: true|false`
- для login/signup/reset_password работающий refresh token
- понятные `error` / `message`

REST replacement:

- `POST /auth/phone/check-registration`
- `POST /auth/login-phone`
- `POST /auth/signup-phone`
- `POST /auth/reset-password-phone`
- `POST /phone-auth/link-email`
- `DELETE /auth/account`

WebSocket replacement:

- не нужен

Поля, которые должны совпадать:

- `exists`
- `isAdmin`
- `refresh_token`
- `session.refresh_token`
- `error`
- `message`

Нельзя менять:

- возможность безопасно открыть сессию только по refresh token
- error semantics, которые UI переводит в user-friendly текст

### `profile_service.dart`

Текущий Supabase usage:

- stream таблицы `users` по `id`
- `getProfile(uid)`
- `updateProfile(uid, data)` через `upsert`
- `uploadAvatar(uid, bytes, contentType)` в bucket `avatars`
- stream profile stats из `listings` и `reviews`

Flutter ожидает:

- строку пользователя с полями `id`, `display_name`, `name`, `email`, `phone`, `avatar_url`, `photo_url`
- avatar upload сразу возвращает public URL
- `streamProfile` обновляется realtime

REST replacement:

- `GET /users/me`
- `PATCH /users/me`
- `GET /users/public/:id`
- `POST /storage/avatar/upload`
- `GET /users/:id/stats` позже

WebSocket replacement:

- `users.profile.updated`
- `users.stats.updated`

Поля, которые должны совпадать:

- `id`
- `display_name`
- `name`
- `email`
- `phone`
- `avatar_url`
- `photo_url`

Нельзя менять:

- fallback-логику UI между `display_name`, `name`, `email`
- наличие `avatar_url` и `photo_url` одновременно

### `listings_service.dart`

Текущий Supabase usage:

- realtime stream таблицы `listings`
- stream feed по category + client-side filters
- stream my listings
- stream listings by owner
- stream similar listings
- `getLatestApprovedListingByOwner`
- `createListing(...)`
- `archiveListing(...)`
- `deleteListing(...)`
- `incrementView(listingId)` через RPC `increment_listing_view`, fallback на row update

Flutter ожидает:

- row listing в snake_case
- `photo_urls` как `List<String>`
- `delivery` как JSON object
- `location` как JSON object или fallback через `city`
- `status` в lowercase: `pending`, `approved`, `rejected`, `sold`, `deleted`, `archived`

REST replacement:

- `GET /listings`
- `GET /listings/:id`
- `POST /listings`
- `PATCH /listings/:id`
- `POST /listings/:id/archive`
- `DELETE /listings/:id`
- `POST /listings/:id/views`
- `GET /listings/owner/:ownerId`
- `GET /listings/:id/similar`

WebSocket replacement:

- `listings.feed.updated`
- `listings.owner.updated`
- `listings.detail.updated`
- `listings.views.updated`

Поля, которые должны совпадать:

- `id`
- `owner_id`
- `owner_email`
- `owner_name`
- `title`
- `description`
- `category`
- `subcategory`
- `price`
- `phone`
- `phone_hidden`
- `city`
- `location`
- `delivery`
- `photo_urls`
- `car`
- `deal_type`
- `real_estate_type`
- `clothes_type`
- `view_count`
- `status`
- `rejection_reason`
- `created_at`
- `updated_at`

Нельзя менять:

- `photo_urls` должен оставаться массивом URL-строк
- `status` только lowercase
- `city` нельзя убирать, даже если есть `location`

### `favorites_service.dart`

Текущий Supabase usage:

- realtime stream таблицы `favorites`
- `toggleFavorite(uid, listingId, makeFavorite)`

Flutter ожидает:

- rows с `user_id`, `listing_id`, `created_at`
- быстрый пересчет `Set<String>` favorite ids

REST replacement:

- `GET /favorites`
- `POST /favorites`
- `DELETE /favorites/:listingId`

WebSocket replacement:

- `favorites.changed`

Поля, которые должны совпадать:

- `id`
- `user_id`
- `listing_id`
- `created_at`

Нельзя менять:

- `listing_id` как строковый идентификатор

### `saved_search_service.dart`

Текущий Supabase usage:

- realtime stream таблицы `saved_searches`
- `saveSearch`
- `deleteSavedSearch`
- `setAlertsEnabled`
- `notifyMatchesForApprovedListing`

Flutter ожидает:

- row `saved_searches` с фильтрами поиска в snake_case
- `alerts_enabled`
- `query_key`

REST replacement:

- `GET /saved-searches`
- `POST /saved-searches`
- `PATCH /saved-searches/:id`
- `DELETE /saved-searches/:id`

WebSocket replacement:

- `saved_searches.changed`
- `notifications.personal.created`

Поля, которые должны совпадать:

- `id`
- `user_id`
- `title`
- `query_key`
- `category`
- `search`
- `subcategory`
- `location`
- `prefer_location_first`
- `radius_km`
- `auto_brand`
- `auto_model`
- `auto_condition`
- `auto_mileage_to`
- `only_uncrashed`
- `alerts_enabled`
- `created_at`
- `updated_at`

Нельзя менять:

- структуру `query_key`
- типы filter-полей

### `follow_service.dart`

Текущий Supabase usage:

- realtime stream таблицы `user_follows`
- `streamFollowersCount`
- `streamIsFollowing`
- `streamFollowedSellers`
- `follow`
- `unfollow`
- `toggleFollow`

REST replacement:

- `GET /follows`
- `GET /follows/:sellerId/status`
- `POST /follows`
- `DELETE /follows/:sellerId`

WebSocket replacement:

- `follows.changed`
- `users.followers.updated`

Поля, которые должны совпадать:

- `follower_id`
- `seller_id`
- `created_at`

Нельзя менять:

- composite identity follower + seller

### `reviews_service.dart`

Текущий Supabase usage:

- realtime stream таблицы `reviews`
- `streamSellerReviews`
- `streamSellerRating`
- `addReview`
- `replyToReview`
- `deleteReview`

REST replacement:

- `GET /reviews?seller_id=...`
- `GET /reviews/rating/:sellerId`
- `POST /reviews`
- `PATCH /reviews/:id/reply`
- `DELETE /reviews/:id`

WebSocket replacement:

- `reviews.changed`
- `reviews.rating.updated`

Поля, которые должны совпадать:

- `id`
- `seller_id`
- `reviewer_id`
- `reviewer_name`
- `listing_id`
- `rating`
- `comment`
- `reply_text`
- `reply_at`
- `created_at`
- `updated_at`

Нельзя менять:

- `reviewer_name` нужен UI, чтобы не падать в "Пользователь"

### `chat_service.dart`

Текущий Supabase usage:

- realtime stream таблицы `chats`
- realtime stream таблицы `chat_messages`
- `getOrCreateChat`
- `markChatRead`
- `markChatDelivered`
- `markChatsDelivered`
- `sendMessage`
- `sendImage`

Flutter ожидает:

- chat rows с `listing_id`, `listing_title`, `buyer_id`, `seller_id`, `last_message`, `updated_at`, `unread_for_buyer`, `unread_for_seller`
- message rows с `chat_id`, `sender_id`, `text`, `image_url`, `created_at`, `delivered_at`, `read_at`

REST replacement:

- `GET /chats`
- `POST /chats`
- `GET /chats/:id/messages`
- `POST /chats/:id/messages`
- `POST /chats/:id/messages/image`
- `POST /chats/:id/delivered`
- `POST /chats/:id/read`

WebSocket replacement:

- `chats.list.updated`
- `chats.message.created`
- `chats.message.delivered`
- `chats.message.read`
- `chats.unread.updated`

Поля, которые должны совпадать:

- chat: `id`, `listing_id`, `listing_title`, `buyer_id`, `seller_id`, `last_message`, `updated_at`, `unread_for_buyer`, `unread_for_seller`
- message: `id`, `chat_id`, `sender_id`, `text`, `image_url`, `created_at`, `delivered_at`, `read_at`

Нельзя менять:

- unread counters по buyer/seller
- `image_url` как строка

### `presence_service.dart`

Текущий Supabase usage:

- upsert в `user_presence`
- stream `user_presence` по `user_id`

REST replacement:

- `POST /presence/online`
- `POST /presence/offline`
- `POST /presence/heartbeat`
- `GET /presence/:userId`

WebSocket replacement:

- `presence.updated`

Поля, которые должны совпадать:

- `user_id`
- `is_online`
- `last_seen`
- `updated_at`

Нельзя менять:

- stale logic на клиенте опирается на `last_seen`

### `notifications_service.dart`

Текущий Supabase usage:

- realtime stream `user_notifications`
- `streamGlobal`
- `streamPersonal`
- `streamUnreadPersonalCount`
- `streamUnreadSavedSearchCount`
- `streamUnreadBadgeCount`
- `markAllSeen`
- `markPersonalReadById`
- `markAllPersonalRead`
- `markSavedSearchNotificationsRead`
- `deleteById`
- `sendGlobal`
- `sendPersonal`

REST replacement:

- `GET /notifications/global`
- `GET /notifications/personal`
- `PATCH /notifications/:id/read`
- `PATCH /notifications/read-all`
- `DELETE /notifications/:id`
- `POST /notifications/push-placeholder`

WebSocket replacement:

- `notifications.global.created`
- `notifications.personal.created`
- `notifications.updated`
- `notifications.deleted`

Поля, которые должны совпадать:

- `id`
- `user_id`
- `scope`
- `type`
- `title`
- `body`
- `payload`
- `is_read`
- `created_at`

Нельзя менять:

- `scope` значения `global` / `personal`
- `is_read` как bool

### `support_service.dart`

Текущий Supabase usage:

- `getOrCreateMyTicketId`
- `createTicketAndSendFirstMessage`
- `sendMessage`
- `streamMessages`
- `streamTicketsForAdmin`
- `adminReply`
- `markReadByAdmin`

REST replacement:

- `GET /support/my-ticket`
- `POST /support/tickets`
- `GET /support/tickets/:id/messages`
- `POST /support/tickets/:id/messages`
- `GET /admin/support/tickets`
- `POST /admin/support/tickets/:id/reply`
- `POST /admin/support/tickets/:id/read`

WebSocket replacement:

- `support.ticket.updated`
- `support.message.created`

Поля, которые должны совпадать:

- ticket: `id`, `user_id`, `name`, `subject`, `status`, `last_message`, `unread_for_admin`, `unread_for_user`, `created_at`, `updated_at`
- message: `id`, `ticket_id`, `sender`, `text`, `created_at`

Нельзя менять:

- `sender` значения `user` / `admin`

### `reports_service.dart`

Текущий Supabase usage:

- `reportListing`
- `streamOpenReports`
- `closeReportDecision`
- `deleteListingById`
- `notifyOwnerViaSupport`
- `notifyOwnerPersonal`

REST replacement:

- `POST /reports`
- `GET /admin/reports/open`
- `POST /admin/reports/:id/close`
- `DELETE /admin/listings/:id`
- `POST /admin/reports/:id/notify-owner`

WebSocket replacement:

- `reports.changed`
- `support.message.created`
- `notifications.personal.created`

Поля, которые должны совпадать:

- `id`
- `listing_id`
- `listing_owner_id`
- `reporter_id`
- `reason`
- `comment`
- `status`
- `decision`
- `admin_uid`
- `admin_comment`
- `admin_note`
- `handled_by`
- `handled_at`
- `closed_at`
- `created_at`

Нельзя менять:

- `status` open/closed semantics

### `admin_service.dart`

Текущий Supabase usage:

- `streamIsAdmin`
- `isAdminOnce`
- `streamPendingModerationCount`
- `streamOpenReportsCount`
- `streamUnreadSupportForAdminCount`
- `streamNeedsAttention`

REST replacement:

- `GET /admin/me`
- `GET /admin/dashboard`
- `GET /admin/users`
- `GET /admin/listings/moderation`
- `GET /admin/reports`
- `GET /admin/support`

WebSocket replacement:

- `admin.dashboard.updated`
- `admin.needs_attention.updated`

Поля, которые должны совпадать:

- `is_admin`
- `uid` compatibility alias if needed
- counts: `pending_moderation_count`, `open_reports_count`, `unread_support_count`, `needs_attention`

Нельзя менять:

- админский UI требует user IDs в ответах

### `feed_ads_service.dart`

Текущий Supabase usage:

- realtime stream `feed_ads`
- `streamAllAds`
- `streamActiveAd`
- `createAd`
- `updateAd`
- `activateAd`
- `deactivateAd`
- `deleteAd`
- `recordImpression`
- `recordClick`
- `uploadAdImage`

REST replacement:

- `GET /feed-ads`
- `GET /feed-ads/active`
- `POST /admin/feed-ads`
- `PATCH /admin/feed-ads/:id`
- `POST /admin/feed-ads/:id/activate`
- `POST /admin/feed-ads/:id/deactivate`
- `DELETE /admin/feed-ads/:id`
- `POST /feed-ads/:id/impression`
- `POST /feed-ads/:id/click`
- `POST /storage/feed-ad/upload`

WebSocket replacement:

- `feed_ads.updated`

Поля, которые должны совпадать:

- `id`
- `title`
- `image_url`
- `target_url`
- `placement`
- `duration_days`
- `is_active`
- `activated_at`
- `expires_at`
- `created_at`
- `updated_at`

Нельзя менять:

- `image_url` должен оставаться готовым public URL

## Hard UI Constraints

Ниже перечислены особенно чувствительные места, которые нельзя менять при миграции:

- Весь data contract для listings, chats, notifications и support должен оставаться в `snake_case`.
- `AuthService.currentUser` в Flutter опирается на наличие имени и аватарки через metadata-like поля. Backend должен отдавать их без дополнительной нормализации на клиенте.
- `Listing.fromMap()` ожидает `photo_urls`, `delivery`, `location`, `view_count`, `status`, `rejection_reason`.
- `Chat.fromMap()` и `ChatMessage.fromMap()` ожидают точные field names из Supabase tables.
- `NotificationsService` считает unread badge на клиенте. Значит `scope`, `is_read`, `created_at` нельзя менять.
- `SupportService` и `ReportsService` используют строки статусов, а не enum objects.
- Для поэтапного cutover backend должен поддерживать смешанный режим:
  - сначала только auth;
  - затем profile;
  - затем listings;
  - затем storage;
  - затем favorites;
  - затем chats;
  - затем admin.
