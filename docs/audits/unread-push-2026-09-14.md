# ATTA: unread / push audit, 2026-09-14

## Architecture before changes

- Chats/read/delivery/inbox: `lib/src/services/chat_service.dart`, `api/chats_api.dart`; backend `modules/chats/chats.service.ts`, controller and gateway. Absolute unread total is buyer/seller counters excluding chats deleted by that participant.
- Notifications: Flutter `notifications_service.dart`, `api/in_app_notifications_api.dart`, `features/notifications/notifications_screen.dart`; backend `modules/notifications/notifications.service.ts`. Personal `isRead`; global per-user `lastNotificationsSeenAt`. CHAT_MESSAGE excluded from notification UI, thus not counted twice. Moderation and support use these same records.
- Badge: `app_badge_service.dart`, wired in `app.dart`. Before changes only chat stream, unused notifications argument, Web skipped.
- APNs: Flutter `push_notification_service.dart`, `api/notifications_api.dart`, native `ios/Runner/AppDelegate.swift`; backend `modules/apns/apns.service.ts`, notifications service. Device token globally unique, reassigned by upsert. Before changes no session ownership; unbind after credentials cleared; Dart token cache not keyed by account. APNs badge only chat payload.
- Android: app_badge_plus launcher adapter; no FCM/provider receiver/service or app notification channel. No background push infrastructure.
- Web: manifest/bootstrap PWA assets, no PushManager subscription, push service worker handler or VAPID sender. No browser notification implementation or Badging API before changes.
- Socket.IO: `chat_socket_service.dart`, backend `chats.gateway.ts`; manual reconnect, heartbeat, joined chat set. Stale connect protected but private event callbacks not protected. Presence `presence_service.dart` and backend `modules/presence`, gateway disconnect updates Redis presence. MainShell also starts heartbeat timer.
- Logout/session lifecycle: `backend_auth_service.dart`, `auth_service.dart`, `app.dart`; auth events reset caches after server logout/local clear. Existing generation protections in auth/token storage must remain.
- Saved search: `saved_search_service.dart`, favorites results UI, `api/saved_searches_api.dart`; backend `modules/saved-searches`. Stored fields include search/category/subcategory/location/radius/car subset AND extended 26-part queryKey (price/year/etc). Old client admin callback fetches only admin's own searches and calls admin send-user; not a reliable cross-user alert flow.
- Publication points: backend `AdminService.approveListing`, admin approved `ListingsService.create`, listing update. Must check actual approved, public owner, photos and deletedAt; never infer approval from client input.
- Red admin attention indicator represents moderation/support/report work queues, not user read flags. It is separate from user notification unread count.

## Regression boundary

Before edits: AppBadgeService serves messages/read/resume/logout. NotificationsService serves personal/global lists, read/seen/delete, saved-search indicators, moderation/support/admin notices and uploads. Socket/presence serve chat join/rejoin, read/delivery events, reconnect/network recovery and online state. Auth serves login/registration/refresh/restore/guest transition/logout. Publication services serve creation, moderation, search/feed, owner archive/resubmit. Existing tests plus focused race/count/matching/token tests must be rerun. No production deployment or migration application authorized.

## Platform references

- Apple APS badge: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/PayloadKeyReference.html
- Android dots depend on active notifications and launcher support: https://developer.android.com/develop/ui/views/notifications/badges
- Web API requires feature detection: https://www.w3.org/TR/badging/ ; https://webkit.org/blog/14112/badging-for-home-screen-web-apps/

## Итог реализации

### Canonical unread / badge

Каноническое правило: **непрочитанные сообщения + непрочитанные пользовательские уведомления**. Сообщения используют уже существующий абсолютный `ChatService.streamUnreadTotal` / buyer+seller counters. Уведомления используют `NotificationsService.streamUnreadBadgeCount`: personal `is_read=false` и global новее персонального `lastNotificationsSeenAt`. Backend `NotificationsService.canonicalBadgeCount` применяет те же правила для каждого получателя APNs.

Уведомления включают generic, moderation, support, saved_search и другие доступные пользователю notification records. `CHAT_MESSAGE` исключён из notifications, поэтому одно сообщение не увеличивает badge дважды. Saved search входит в общий notification count один раз, даже если показывает точки сразу на двух вкладках. Админская точка `streamNeedsAttention` — очередь модерации/обращений, не пользовательский unread: её чтение не завершает задачи, поэтому она не прибавляется к этому счётчику.

`app_badge_service.dart` теперь слушает оба источника, берёт начальный notification count из кэша и сериализует записи. При logout очищает state и badge; поколение сессии защищает от поздних записей A поверх B. Сетевые ошибки больше не трактуются как «всё прочитано». Resume сохраняет существующий refresh inbox/notifications. Снят лимит первых 200 notification records, чтобы старые unread не исчезали из счётчика; список сейчас остаётся без pagination, как исходный API. На больших историях уведомлений это отдельная задача оптимизации API, не выполненная здесь.

В `notifications_service.dart` добавлены session guards для refresh/read/delete и realtime-ingestion. `markAllSeen` очищает также realtime-слой, который раньше оставлял unread поверх серверного состояния. Server refresh заменяет старый realtime record того же ID. Исправлена изменяемость списка для delete.

### iOS / APNs

- Сохранены `app_badge_plus` для локальных чисел и собственный native APNs канал. APNs теперь получает canonical `aps.badge` для всех типов уведомлений, а не только chat unread.
- Native `unregister` при logout отключает remote registration, обнуляет иконку, очищает доставленные/ожидающие уведомления и начальный/buffered tap.
- Flutter token-bind привязан к user/generation, поздний результат A игнорируется. Новый user регистрирует даже тот же физический token. Повторное открытие приложения получает native token заново; обновлённый токен подхватывается при следующем bind/resume.
- Push payload содержит `recipientId`; чужие и поздние taps отфильтровываются. Общая notification navigation также проверяет владельца и смену аккаунта во время read.
- Исправлена ES256 подпись provider JWT: Node по умолчанию возвращал DER, для JWT нужен raw 64-byte R||S. Тест проверяет длину и криптографически верифицирует подпись синтетическим EC-ключом. Основание: [RFC 7518 §3.4](https://www.rfc-editor.org/rfc/rfc7518.html#section-3.4).
- Локального файла APNs-ключа по настроенному пути **нет**. Реальная валидность server credentials, доставка APNs, killed/background и внешний iOS badge на устройстве не проверялись. Уже отправленные внешнему провайдеру payload не покрыты гарантией отмены этой клиентской логикой.

### Android

В проекте нет FCM/другого Android push sender, receiver/service или собственного канала уведомлений. Добавлять провайдера без согласованной инфраструктуры не стали. Имеющийся `app_badge_plus` получает canonical число/ноль для поддерживаемых launchers. Это **не** реализует Pixel notification dot: для dot требуется активное системное уведомление. Число на Samsung/совместимых launchers зависит от launcher и разрешений; отсутствие цифры на Pixel не является дефектом счётчика ATTA. Android background/killed push и очистка системных push-уведомлений остаются инфраструктурным блокером.

### Web / PWA

Добавлен условный `platform_badge_web.dart`: secure-context feature detection и реальные `navigator.setAppBadge` / `clearAppBadge`. Неподдерживаемый браузер и отказ разрешения не ломают приложение. В Chrome локально проверены API-вызовы 1/2/3/0; capability `supported=true`. Это не визуальная проверка установленной PWA-иконки.

Browser notifications, PushManager subscriptions, push-handler service worker, VAPID keys и backend Web Push sender отсутствуют. Поэтому Web badge обновляется при работе страницы/синхронизации приложения; закрытая PWA не получает новые события. Для полного Web push нужны отдельные конфигурация/ключи/хранение subscriptions и согласованная серверная реализация. Фиктивный push не добавлялся.

### Saved search

Новый backend `saved-search-alerts.service.ts` вызывается из `AdminService.approveListing`, approved-create и перехода в approved в `ListingsService`. Старый Flutter admin callback, который видел только saved searches админа, удалён. Обычный поиск не переписывался.

Matching проверяет текущий APPROVED, `deletedAt=null`, фото и активного не удалённого владельца. Собственные объявления, disabled/deleted searches и поиски, созданные после даты публикации, исключены. Текст использует существующий `buildListingSearchWhere`, включая реальные поисковые поля; категория/подкатегория/location/car-фильтры проверяются по сохранённым данным. Расширенный 26-part queryKey уже хранит price/year/transmission и другие параметры — они также учитываются.

Семантика location сохранена от текущей ленты: без radius это предпочтение сортировки, с radius — текстовое совпадение locality. Координат центра в saved search нет, поэтому географические километры не выдуманы. `onlyUncrashed` сохраняет существующую консервативную текстовую эвристику ленты; это не достоверная история ДТП.

`SavedSearchAlert` имеет составной PK `(savedSearchId, listingId)`. Row-lock saved search сериализует matching с delete/disable, проверка listing выполняется под shared lock. Ledger и notification создаются одной транзакцией; `skipDuplicates` не допускает повторного alert при конкурентном вызове. Удаление notification не удаляет ledger, повторное одобрение не возвращает тот же alert.

Создаётся personal `SAVED_SEARCH` с `listingId` и `savedSearchId`; дальше действуют общий unread, socket event, существующий APNs sender и новый navigation case, открывающий конкретное объявление. Нажатие использует общий mark-read.

Ограничение надёжности: matching запускается после записи публикации, без нового outbox/worker. Ошибка БД/процесса логируется; повторное одобрение безопасно повторяет создание пропущенных записей. Нет автоматической гарантии восстановления после падения между publication и matching, как и повторной доставки при падении после commit notification. Для такой гарантии нужен отдельный durable job/outbox — архитектурная работа вне минимальной задачи.

### Logout / socket / presence / device ownership

App binder начинает сброс user-specific сервисов синхронно до ожидания futures; завершение старого logout не запускает новые сбросы уже после входа B. Socket disconnect очищает listeners, heartbeat, reconnect timer и chat subscriptions. Проверки экземпляра, поколения auth и socket session отсекают старые event/error/disconnect и события, уже поставленные в Dart stream queue. Старый disconnect не останавливает heartbeat B; отменённый connect attempt не оставляет зависший completer. Presence reset инвалидирует ожидающие запросы, старый UID не отправляет heartbeat/offline от имени B. MainShell не создаёт heartbeat после своего disposal/смены UID. Добавлены guards inbox HTTP/cache restore.

Backend `UserDevice.sessionId` привязывает token к существующей сессии. Logout деактивирует устройства этой сессии. APNs выборка требует active device и незавершённую, неистёкшую session. Registration сериализуется advisory lock по token, отвергает отозванную/более старую сессию и переназначает token новому user/session. Поздний unregister A ограничен `userId=A` и не выключает B.

## Миграции и порядок обновления

Созданы две миграции:

1. `20260914180000_push_device_session`: nullable session FK на `user_devices`; старые токены без доказуемой сессии деактивируются.
2. `20260914181000_saved_search_alerts`: ledger с составным PK и cascade FK.

Проверены локально: временная PostgreSQL 16, исходная текущая схема без этих двух добавлений, затем обе миграции. Prisma diff реальной итоговой схемы — **empty migration**. Production и существующие базы не использовались. Временная БД остановлена после проверки.

Сервер нужно обновить вместе с миграциями до использования нового client flow. Старые token registrations потребуют обновления/перезапуска клиента и re-register; миграция намеренно не сохраняет доставку на токены с неизвестной сессией. Flutter-обновление также требуется для полного cleanup и суммарного badge. Ничего не деплоилось и не публиковалось.

## Проверки

| Проверка | Результат |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test --no-version-check` | 699 passed, 6 skipped; дополнительно конечный socket suite 45 passed |
| Chrome: Badging API + badge/unread + saved search + guest sheet | 10 passed; реальный Badging API supported=true |
| Дополнительные notification navigation tests | 12 passed, включая saved_search route |
| Presence + guest regression | 16 passed, включая A logout/B heartbeat |
| `flutter build web --release --no-version-check` | Успешно, финальный код |
| `flutter build apk --debug --no-version-check` | Успешно, финальный код |
| `flutter build ios --debug --no-codesign --no-version-check` | Успешно, финальный код |
| `npx prisma validate` | Schema valid |
| Backend relevant tests (notifications, saved-search, auth, chats service/gateway, APNs, listings, admin, users, wallet, support) | 229 passed |
| Настоящая PostgreSQL integration (`unread-push.integration.spec.ts`) | 1 passed; concurrent dedup, filters/statuses, deleted search, read/seen counts, APNs metadata, token A→B |
| NestJS application context / dependency graph | OK, publication hooks injected в ListingsService/AdminService |
| `npm run build` | Успешно, после финального backend исправления |
| Source `git diff --check` | Чисто; generated Prisma node_modules имеют служебный whitespace |

Полный Flutter suite повторно покрывает guest/auth sheet, login/registration/logout, stale refresh, restore credentials, favorites/profile/wallet, inbox/read/reconnect, notification navigation и listings/moderation. Backend fixtures phone signup дополнены уже обязательными согласиями; в own-profile тесте уточнён union type перед проверкой `phone`. Guest sheet test теперь отдельно ожидает существующие Web-only кнопки магазинов. Продуктовая auth/guest логика ради этих тестов не изменялась.

Web build предупреждает о существующей несовместимости `socket_io_common` с Wasm dry run и отсутствующей CupertinoIcons font family. Обычная release JS-сборка успешна; Wasm не заявляется.

iOS Simulator обнаружен (iPhone 17 Pro, iOS 26.2), но реальные сообщения/login/APNs/badge в нём не запускались: отсутствуют изолированный мобильный backend flow и push credentials. Android Emulator не запущен. iOS device compilation без подписи не считается runtime-тестом. Chrome проверен тестовым runner, не полноценным production/PWA deployment.

## Воспроизведение локального integration test

Тест требует отдельной подготовленной PostgreSQL с этой схемой и явного opt-in; никогда не использует production `DATABASE_URL` как fallback:

```sh
ATTA_UNREAD_TEST_DATABASE_URL=postgresql://istamal@127.0.0.1:55439/postgres \
  node --test -r ts-node/register \
  apps/api/src/modules/saved-searches/unread-push.integration.spec.ts
```

Из папки backend. Тест проверяет localhost/порт, создаёт только синтетических пользователей/объявления и удаляет свои записи. APNs и socket gateway замоканы; реальными являются Prisma, PostgreSQL, транзакции, locks, uniqueness, notifications и session lifecycle. Runtime реальной доставки APNs этим не заменяется.
