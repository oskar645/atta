# Account deletion: dependency map recorded before implementation

Scope: existing working tree on 2026-09-15. No production DB, S3, account deletion or deployment. Existing unrelated edits preserved. Read-only code audit, local tests/mocks only.

## Entry points and existing behavior

Flutter SettingsScreen._deleteAccount: irreversible confirmation -> AuthService -> BackendAuthService.deleteAccount -> DELETE /auth/account -> JwtAuthGuard -> AuthService.deleteAccount. BackendAuthService currently clears native/server restore credentials BEFORE deletion and clears local session after success; settings then calls signOut again. Auth events in app.dart reset wallet, notification, admin, support, presence, chats, follows, favorites, listings, profile, history, reviews, badge/push. SavedSearchService has a separate cache with no session reset.

Admin DELETE /admin/users/:id uses AdminService.performSoftDeleteUser, a duplicate lifecycle with protected-admin checks. Both paths delete avatar, listing photos (including DB photo rows), and ALL participants' chat images before a DB transaction. Transaction hides ALL chat messages and both participants' chat entries, deletes favorites/searches/views/follows/notifications, soft deletes authored reviews and listings, nulls support sender, anonymizes support ticket name and User, revokes sessions. User itself is NOT hard deleted. External/DB photo cleanup can succeed before subsequent failure, leaving an active, damaged account.

## Dependency and regression map

| Entity | Existing relation / delete action | Consumers and actual retention before fix |
|---|---|---|
| User | Retained DELETED tombstone | Auth, sellers, chats, reviews, admin, finance. Name/avatar/phone anonymized; synthetic email; password hash, last login remain. |
| UserSession | User CASCADE; device session SET NULL | HTTP guards and refresh; revoked but refresh hash, IP, agent/device fields remain. |
| UserDevice | User CASCADE | APNS/session-bound push; active push tokens, device UID and binding remain. |
| RestoreCredential | User CASCADE | Android restore auth checks user status, but public key/device/credential remain; another device not explicitly revoked. |
| UserPresence | User CASCADE + Redis TTL 120s | Presence API/socket; row and already-connected sockets remain. Gateway authenticates only on connection. |
| Listing | owner CASCADE | Feed/search/seller/admin/moderation; all nondeleted states become DELETED. ownerName/email/phone/address/GPS/JSON remain. |
| ListingPhoto | listing CASCADE | Public photos; deleted before transaction. Listing snapshots/chat previews may reference them. |
| ListingModerationRevision | listing CASCADE | Moderation snapshot JSON remains and may contain original identity/content/media. |
| Favorite, SavedSearch, ViewedListing | user/listing CASCADE | Private lists removed; SavedSearchAlert cascades with search. |
| ListingView | listing CASCADE; viewer ID has NO user FK | View counts/analytics/anti-duplicate device; user/device/IP remain. |
| UserFollow | both users CASCADE | Follow lists/counters; edges removed. |
| Review | both users CASCADE; listing SET NULL | Authored reviews hidden, reviewerName/comment retained; reviews about A and replies retained. |
| Chat / ChatMessage | users CASCADE; chat listing SET NULL | B's history is hidden too; raw text remains; attachments physically deleted for A and B. Identity from related User. |
| ChatPeerBlock | both users CASCADE | Private chat block edges remain. |
| UserNotification | user CASCADE | A's notifications removed; B's denormalized bodies/payloads may retain A's name/text. |
| SupportTicket/Message | ticket user CASCADE; sender SET NULL | Name anonymized, sender nulled; messages and attachment URLs embedded in text retained for support/admin. Protected support media endpoint. |
| Report | reporter CASCADE; listing/owner/handler SET NULL | Reports retained, owner nullified for A's listings; free text retained. |
| UserBlock / BlockedIdentity | target CASCADE; issuing admin RESTRICT; lifting admin SET NULL | Security/admin appeals; phone retained for block enforcement. |
| Wallet / WalletTransaction / Payment | user CASCADE | Retained because User remains; balances, provider IDs, idempotency keys, metadata and payment callbacks preserved. No separately modeled receipt/refund retention policy found. |
| Referral | inviter/invited CASCADE; transaction SET NULL | Existing rewards/history retained; confirmed PhoneVerification SIGNUP + createdUserId is anti-repeat-referral evidence. |
| PhoneVerification | NO user FK | Phone, IP/device, provider/check/metadata retained. Same phone registration creates a NEW UUID; prior confirmed signup prevents another referral reward. Deleting this evidence would introduce abuse. |
| Promotion / ListingRaiseCampaign | user/listing CASCADE | Paid history remains; active promotions not explicitly cancelled by delete. |
| UserConsent | user CASCADE | Acceptance/technical metadata retained as evidence. Marketing withdrawal not part of original delete. |
| AppDailyVisit | user CASCADE | Identifiable usage history remains. |
| AuditLog | actor SET NULL | Admin/security old/new JSON and IP remain. No documented retention schedule. |
| FeedAd | creator SET NULL | Admin ad content preserved; not ordinary user's private data. |

CASCADE/SET NULL/RESTRICT above describe schema hard-delete behavior, NOT actions triggered by the current soft delete. Hard deleting User would destroy finance and third-party history and is unsafe.

## Media ownership and constraints

Avatars: profile URL/photo URL, modern S3 keys scoped by user; legacy local names and externally supplied URLs do not prove exclusive ownership. Listings: ListingPhoto storage key, retained moderation snapshots. Chats: ChatMessage sender + chat participant authorization, protected /media/chats/:id. Support: attachment URL embedded in text, ticket authorization. Misc/video/upload URLs do not have a complete ownership registry. Public object proxy/local static paths and direct S3 URLs mean removing DB references alone cannot revoke already-known public URLs. No production object enumeration or deletion performed.

## Decisions before edits

Keep mixed anonymization/soft-delete with retained financial/security/support history. Preserve B's chat history/attachments; hide only A's side. Keep existing authored-review hiding and listing DELETED behavior. Clean explicit private identifiers/credentials and denormalized listing/review identity. Preserve signup phone evidence, block identities, finance, moderation/audit and free-form historical content pending product/legal retention decisions; do not claim complete erasure.

Use one shared deletion implementation for self/admin paths, a DB transaction, and a small durable media cleanup job committed with tombstone. External cleanup follows commit and retries, without reactivating the account. Public deletion masking is also needed for legacy tombstones. Existing auth/listings/chats/wallet architecture otherwise stays intact.

## Итог реализации

Подтверждённые проблемы исправлены локально. Production не деплоился; реальные аккаунты, production DB и production S3 не изменялись. Модель остаётся смешанной: soft delete User/listings/reviews, очистка прямой идентичности, физическое удаление приватных DB-записей и безопасно определённых avatar-объектов. Сохранённый userId позволяет связать финансовую/служебную историю: это не гарантия необратимого обезличивания всех исторических данных.

### Что изменилось

1. `AccountDeletionService` объединяет ранее дублированные self/admin операции. `AuthService.deleteAccount` и `AdminService.performSoftDeleteUser` используют его; административные запреты удаления себя/защищённого/последнего администратора остаются в исходном endpoint flow. Self-delete admin-профиля по-прежнему запрещён.
2. Критические изменения выполняются одной Prisma interactive transaction с уровнем SERIALIZABLE. Сначала обновляется User, затем создаётся cleanup-job и очищаются зависимости. Конфликты сериализации P2034 повторяются максимум три раза. Реальный PostgreSQL-тест обнаружил конфликт создания job при одновременном удалении; порядок исправлен и проверен повторно.
3. Физическое удаление media выполняется после commit. `AccountDeletionCleanup` сохраняется в той же транзакции, поэтому переживает остановку процесса после commit. Worker проверяет до 20 задач каждые 30 секунд; при ошибке откладывает следующую попытку на 60 секунд. Успешная задача удаляется. При ошибке S3/Redis API не превращает уже выполненное DB-удаление в отказ и не активирует аккаунт обратно. Неактивный storage provider не считается успешным физическим удалением.
4. Повторный вызов для уже удалённого User не меняет timestamp удаления и продолжает существующий cleanup-job. HTTP со старой сессией закономерно получает 401; идемпотентный повтор media выполняет worker, а не неавторизованный клиент.

### Физически удаляемые DB-данные

- Все `UserDevice` и `RestoreCredential` аккаунта, включая второе устройство.
- Favorites, SavedSearch и каскадные SavedSearchAlert, ViewedListing, AppDailyVisit, UserPresence.
- Обе стороны UserFollow и ChatPeerBlock, относящиеся к удаляемому аккаунту.
- Его личные UserNotification.

`ListingView` сохраняет сам факт просмотра для счётчиков, но viewerUserId, viewerDeviceId и IP очищаются. Записи другого пользователя не очищаются.

### Обезличивание и sessions

- User: phone → null, phoneVerified → false, email → технический `deleted+UUID@atta.local`, displayName/name → «Удалённый пользователь», avatarUrl/photoUrl → null, passwordHash → пустая строка, lastLoginAt/lastNotificationsSeenAt → null. Статус DELETED и deletedAt сохраняют tombstone.
- Все UserSession отзываются; refresh hash, IP, userAgent, deviceId/deviceName очищаются. HTTP guard и refresh проверяют реальное состояние сессии/пользователя. Существующие JWT второго устройства также перестают работать.
- Gateway отключает всю комнату `user:UUID` после commit; каждый последующий socket event заново проверяет access token, сессию и deleted-статус. Presence DB очищена, Redis presence удаляется post-commit с повтором при сбое.
- Public profile, chat participant preview и reviews маскируют прямую идентичность также у старых DELETED tombstones с оставшимися исходными полями. Это защита чтения; миграция не переписывает ранее удалённых production-пользователей.
- SupportTicket.name обезличивается, SupportMessage.senderUserId становится null. Содержание переписки поддержки остаётся.
- Review.reviewerName обезличивается. В известных `review_new` уведомлениях других пользователей заменяется скопированное имя автора; само уведомление и его связь с отзывом сохраняются.
- Marketing consent получает withdrawnAt; доказательства принятия Terms/personal-data consent не уничтожаются.

### Объявления и продвижение

Сохраняется исходное правило удаления: APPROVED/PENDING/REJECTED/ARCHIVED/SOLD без deletedAt переводятся в DELETED, publishedAt очищается. Уже DELETED записи остаются удалёнными. Все объявления A, включая ранее удалённые, теряют ownerName/email, phone, точный address/GPS/locationJson. Публичный listing endpoint не выдаёт удалённое объявление обычному посетителю. User-facing owner identity скрыта.

ACTIVE Promotion и ListingRaiseCampaign отменяются, nextRaiseAt очищается. Исторические цены, расходы, wallet/payment records сохраняются. Автоматический refund не придуман: правила возврата за остаток продвижения требуют продуктового решения. Снимки модерации, описания и фотографии исторических объявлений сохранены.

### Чаты и отзывы

В чатах меняются только deletedByBuyerAt/unreadForBuyer либо deletedBySellerAt/unreadForSeller для стороны A. LastMessage, сообщения обеих сторон, вложения, unread и видимость истории B сохраняются. Имя/аватар удалённого собеседника берутся из обезличенного User; legacy preview также защищён. Авторизованный B продолжает получать свои chat attachments через защищённый endpoint.

Существующая модель authored reviews сохранена: отзывы A помечаются deletedAt и их reviewerName обезличивается. Отзывы других людей об A, тексты/replies и рейтинги не уничтожаются. Свободный текст может содержать персональные сведения — автоматической произвольной редакции исторических сообщений/отзывов нет.

### Media

- Очередь хранит оба исходных avatarUrl/photoUrl и удаляет только распознанные URL настроенного storage. S3 key должен принадлежать `avatars/UUID/`; local filename проходит проверку. Чужие префиксы, traversal и внешние URL не приводят к удалению.
- Дополнительно проверяются ссылки других User на тот же файл, включая encoded proxy URL; общий объект физически не удаляется.
- Scoped avatar через `/media/object` становится недоступен сразу после DB commit, даже если S3 недоступен.
- ListingPhoto и chat attachments больше не уничтожаются вместе с аккаунтом; они нужны оставленной исторической сущности/собеседнику. Support attachments остаются с обращениями и защищённым доступом.
- Legacy/external/shared avatars, orphan uploads, misc/videos/reports uploads не имеют полного реестра доказанного владения. Массовая очистка не выполнялась. Уже известные прямые public S3/local URL, копии в клиентском кеше и исторические listing photos нельзя считать отозванными только по DB tombstone. Для полного ограничения такого доступа нужны отдельно согласованные retention и модель доступа к историческим media.

### Wallet, payments, referrals, support и audit

Wallet, WalletTransaction, Payment, providerPaymentId/idempotencyKey, Referral, Report, UserBlock/BlockedIdentity, AuditLog и ListingModerationRevision сохраняются. Их CASCADE не срабатывает, поскольку User физически не удаляется. Техническая ссылка userId остаётся для бухгалтерии, callbacks, идемпотентности и antifraud. Callback оплаченного платежа по существующей модели может завершить начисление в исторический wallet; повторное начисление защищено прежней идемпотентностью. Новый аккаунт этот wallet не получает. Политика refunds/receipts и сроки хранения не задавались.

PhoneVerification с createdUserId сохраняет phone/purpose/status/createdUserId: текущая referral-проверка использует ранее подтверждённый SIGNUP этого телефона. У таких записей удаляются requestedByIp/requestedByDeviceId, истекает verification. BlockedIdentity.phone остаётся для запрета обхода блокировок. Остальные verification/security/provider metadata, audit IP/JSON, moderation snapshots и свободный текст не стираются без решения о retention.

### Повторная регистрация

Тот же освобождённый телефон после нового подтверждения создаёт новый User UUID, новую сессию и новый wallet по существующим правилам bootstrap/бонусов. Старые tokens, private data и баланс не привязываются к новому аккаунту. Подтверждённый прежний SIGNUP сохраняется и предотвращает повторный referral reward по этому телефону. Правило регистрации и welcome/daily бонусов не изменено; это не введение отдельной проверки идентичности физического лица между разными номерами.

### Flutter

BackendAuthService сначала ждёт `deleted: true`; при ошибке/отрицательном ответе не отзывает заранее restore credential и не изображает успешное удаление. После успеха очищает currentUser, secure tokens и кеш пользователя, увеличивает session generation, отправляет signedOut, очищает native restore/state. Ошибка Credential Manager не отменяет guest mode. Поздние ответы refresh/profile/delete A не перезаписывают сессию B.

SettingsScreen сохраняет исходное подтверждение серьёзного необратимого действия; повторный `signOut()` после успешного удаления убран. Подпись уточнена: удаление профиля и снятие объявлений с публикации, поскольку обещание физического удаления всех связанных данных не соответствует архитектуре.

Существующий signedOut binder сбрасывает wallet, notifications, support/admin, chats/socket, presence, follows, favorites, listings, profile, viewed history, reviews, badges/push binding. Добавлен отсутствовавший сброс SavedSearchService, включая защиту от повторного заполнения кеша запоздавшим ответом A.

## Проверки и доказательства

| Проверка | Результат |
|---|---|
| Исходный backend suite до изменений | 434 passed, 1 skipped, 0 failed |
| Итоговый полный backend suite | 456 passed, 2 skipped, 0 failed |
| Отдельный PostgreSQL deletion integration test | passed; реальный rollback, две сессии, CASCADE SavedSearchAlert, конкурентное удаление, сохранность B/finance/chat, post-commit mock S3 failure/retry |
| Prisma validate | passed |
| Новая миграция | generated offline diff совпадает с migration.sql; CREATE TABLE/INDEX успешно применены только в изолированном временном PostgreSQL |
| npm run build | passed |
| flutter analyze | No issues found |
| flutter test --no-version-check | 706 passed, 6 skipped, 0 failed |
| flutter build web --release --no-version-check | passed, build/web |
| flutter build apk --debug --no-version-check | passed, build/app/outputs/flutter-apk/app-debug.apk |
| flutter build ios --debug --no-codesign --no-version-check | passed, build/ios/iphoneos/Runner.app |
| git diff --check для исходников/Prisma/lib/test/docs | passed |

Шесть старых падений signup с `Terms acceptance is required` не воспроизвелись ни в исходном backend suite, ни после изменений; delete-изменения не меняют signup consents. Шесть Flutter skips — уже существующие тесты `profile_screen_test.dart`, не Terms failures. В полном backend suite пропущены opt-in PostgreSQL tests: существующий unread-push и новый deletion. Новый deletion отдельно выполнен с явным безопасным test URL; существующий unread-push integration требует другого заданного environment и в этом запуске не включался.

Web build содержит предупреждения о wasm dry-run в `socket_io_common` и CupertinoIcons font. Обычная запрошенная web release-сборка успешна; эти зависимости/asset-настройки не менялись. Сгенерированный Prisma client в tracked node_modules имеет generator whitespace; его ручная правка не выполнялась.

Новые regression tests находятся в:

- `backend/apps/api/src/modules/auth/account-deletion.service.spec.ts`: обе сессии, старые JWT/refresh, private cleanup, B isolation, listing states/promotions, history retention, public identity, DB rollback, retry/idempotency, same-phone signup/referral, self/admin routing и DI optional saved-search alerts.
- `backend/apps/api/src/modules/auth/account-deletion.postgres.spec.ts`: opt-in тест только для фиксированного временного Unix socket/database; никогда не использует DATABASE_URL по умолчанию.
- `backend/apps/api/src/modules/storage/account-avatar-cleanup.spec.ts`: ownership, encoded/shared references, local/provider errors, traversal/foreign URL.
- Добавления в media controller tests: deleted avatar недоступен, active avatar доступен.
- `test/services/backend_auth_service_test.dart`: успешный/ошибочный delete, native failure, secure storage/restore state, guest event, late refresh и A→B.
- `test/services/saved_search_service_test.dart`: очистка кеша и игнорирование запоздавшего ответа A.

Полные suites дополнительно проверили прежние login/signup/logout/restore/guest/A→B, создание/модерацию объявлений, чаты/realtime, wallet/payments/referrals, reviews/favorites, support/admin. Это code/unit/widget и локальная PostgreSQL проверка; production runtime deletion, реальный S3/APNS и взаимодействие двух физических устройств не выполнялись.

## Миграция и оставшиеся решения

Нужна новая миграция `20260915120000_account_deletion_cleanup` перед запуском обновлённого backend. Она добавляет только таблицу post-commit cleanup и индекс; существующие FK/cascade и финансовая схема не меняются. Production миграция не применялась, сервер не обновлялся. Перед будущим выпуском следует учитывать остальные уже имеющиеся изменения/миграции рабочего дерева; они не создавались этой задачей.

Согласования требуют: сроки и основания хранения phone-verification/block identities, provider/audit metadata и IP, moderation snapshots, historical text/media, receipts/refunds и остатки продвижения. Полное стирание персональных данных из этих источников не заявляется. Старые production tombstones не подвергались массовому backfill/cleanup. Загруженные ранее копии media/уведомлений на устройствах удалённо не стираются.

Текущая PM2-конфигурация проекта задаёт один процесс. Немедленное отключение socket-room происходит в этом процессе; для нескольких независимых инстансов нужен межпроцессный disconnect-сигнал/adapter. Проверка каждой socket-команды уже не допускает работу удалённой сессии, однако это не гарантия немедленного отключения молчащего socket на другом инстансе.

Временный PostgreSQL-кластер после проверок остановлен. Production deployment, миграции и очистка production media не выполнялись.

Flutter изменения: да
Backend изменения: да
Нужно обновить сервер: да
