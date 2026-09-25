# Admin Dashboard: гости, открытия, сообщения

## Результат

- Гости: сегодня / вчера / 7 календарных дней / текущий месяц / всё время — готовы.
- Открытия: guest / registered / total, все пять периодов — готовы.
- Отправленные сообщения и активные диалоги, все пять периодов — готовы.
- Активные пользователи сообщений не добавлены: «отправил» и «участвовал» дают разные метрики.
- Flutter изменения: да. Backend изменения: да. Нужно обновить сервер: да.
- Migration нужна: да, только additive. Commit/push/deploy и публикация сборок не выполнялись.

## Аудит и определения

`AppDailyVisit` уже хранит зарегистрированные посещения по user/day. Его текущий Dashboard-блок и бизнес-логика сохранены. Для гостей эта таблица непригодна: обязательный userId/FK. Переиспользованы существующий бизнес-часовой пояс `WALLET_TIME_ZONE` (по умолчанию Europe/Moscow), Socket.IO, guards и случайный `atta.viewerDeviceId`.

`ListingView` обслуживает публичный счётчик с lifetime-уникальностью listing/device и особыми правилами owner/admin. Он не менялся. Новое открытие фиксируется отдельно после загрузки ListingDetail, один UUID события на State экрана. Rebuild, повторный callback и обновление данных не дают новое событие; закрытие и новое открытие создают новый UUID. Переходы из admin blocks/reports/promotions и похожие объявления внутри таких экранов исключены. Админ в обычной пользовательской части считается registered.

Guest ID — существующий случайный UUID v4, Web localStorage / Android и iOS SharedPreferences. Параллельная инициализация сериализована, ключ не очищается при login/logout. IP, имя, телефон, email и fingerprint не используются как identity. В новой БД нет raw IP или персональных данных. IP используется только существующим rate limiter. Очистка storage, другой браузер, incognito или новая установка без восстановленного storage могут дать нового гостя. При недоступном storage событие пропускается, случайный новый ID на каждый запрос не генерируется.

Guest activity отправляется на старте, при logout и возврате в приложение. Backend проверяет optional JWT: при нормальной сессии guest-запись не создаётся, неверный JWT отклоняется. История не переклассифицируется при login/logout. За период считается DISTINCT guestId, а не сумма дневных уникальных гостей. История гостей/открытий начинается с внедрения сбора, прошлые значения не восстанавливаются.

Сообщения считаются из существующей `chat_messages`: TEXT и IMAGE, включая сохранённые soft-deleted строки. Активный диалог — DISTINCT chat_id с хотя бы одной такой строкой в периоде. Support использует отдельные `SupportTicket`/`SupportMessage` и исключён. Typing, presence, delivery/read, reconnect и push не создают аналитические строки. Hard-delete/cascade существующих сообщений уменьшает доступную историю; отдельного неизменяемого архива сообщений задача не вводит.

Периоды используют полуоткрытые границы: сегодня от местного 00:00 до snapshot, вчера до сегодняшнего 00:00, неделя — текущий день и шесть предыдущих, месяц — от первого числа. UTC timestamps преобразуются явно, независимо от timezone PostgreSQL-сессии.

## Хранение, API и realtime

Source of truth — PostgreSQL (`analytics_guest_days`, `analytics_listing_opens`, существующая `chat_messages`).

- `POST /analytics/guest-activity`: UUID гостя, optional JWT, unique guest/day + ON CONFLICT DO NOTHING.
- `POST /analytics/listing-open`: UUID события и объявления, optional JWT; registered выводится только из сессии. UUID события — primary key, повтор после login не меняет классификацию.
- `GET /admin/dashboard/usage`: JwtAuthGuard + AdminGuard, все периоды одним MVCC snapshot (RepeatableRead).
- Вставки не делают COUNT/SUM. Dashboard использует индексируемые range predicates, covering indexes, coalescing одновременных запросов и cache до 1 секунды с invalidation после записи.
- После записи guest/open и после commit реального text/image Message отправляется только сигнал изменения. Существующий chat duplicate path не отправляет дополнительный сигнал.
- Существующий ChatsGateway обрабатывает `analytics.subscribe`; вход в `admin:analytics` требует активную сессию и admin по тем же DB/phone правилам. Перед уведомлением подписчика повторно проверяются сессия и admin. Обычные пользователи событие не получают.
- Backend объединяет сигналы за 500 мс; Dashboard объединяет их за 1200 мс и перезапрашивает API. Reconnect повторяет подписку и refetch. Есть кнопка обновления, refetch при resume и fallback каждые 30 секунд. Локальных арифметических инкрементов нет.
- Существующая конфигурация PM2 — один процесс. Для будущего горизонтального масштабирования потребуется общий канал invalidation/существующий Socket.IO adapter; polling уже обеспечивает восстановление между процессами, но мгновенность между ними не обещается.

## Migration и ограничения перед внедрением

`20260922160000_usage_analytics` добавляет две таблицы и индексы. Старые строки и публичные views не меняются. Индекс `chat_messages(created_at, chat_id)` создаётся CONCURRENTLY: migration нельзя оборачивать во внешнюю транзакцию. Migration проверена только на одноразовой локальной PostgreSQL, не на сервере приложения.

Перед включением клиента нужны обычное обновление backend с Prisma Client и применение migration. Сгенерированные JS в `dist` восстановлены из рабочей копии до build, отслеживаемый Prisma Client — из исходного состояния. Служебный `dist/tsconfig.tsbuildinfo` обновлён проверками. Проверки backend выполнялись после локального `prisma generate` / `npm run build`; перед повторным lint нужно снова выполнить `npx prisma generate`.

События клиента best-effort: offline/сбой storage/запроса может дать недоучёт; постоянная очередь не вводилась. Native storage проверен Flutter-тестами SharedPreferences, Web — реальным localStorage в тестовом Chrome. Полный ручной прогон на физических Android/iOS и production-scale EXPLAIN не выполнялись.

Индексы доступны и для all-time; точные COUNT/DISTINCT всё равно зависят от объёма истории. На синтетических 250000 Message + 250000 opens + 100000 guest-days полный запрос: около 259 мс после прогрева, 1631 мс на первом запросе с подключением Prisma. Это локальный ориентир, не SLA. На минимальных fixture-строках PostgreSQL может предпочесть sequential scan covering-индексу для всей истории. При существенно большей базе следует проверить планы на репрезентативной копии перед rollout; миллионы Message не дублировались в analytics.

## Проверки

- `npx prisma validate`, `npm run lint`, `npm run build` — прошли с локально сгенерированным Prisma Client.
- 170 backend-тестов — прошли, без skipped. Включены analytics, listings, admin, chats/gateway, шесть PostgreSQL-тестов (включая родительский).
- PostgreSQL: 20 конкурентных повторов, guest/day unique, distinct по периоду, guest home без opens, immutable classification при login, реальные новые opens, Москва/границы дня, недели, месяца и года, сообщения/active chats, support отдельно, delivery/read/soft-delete не увеличивают метрики.
- Backend regression: повтор sendMessage с clientMessageId вызывает одно analytics invalidation после commit; повтор delivery — ни одного. Доступ к API/realtime, отозванная сессия, coalescing/refetch проверены.
- 87 Flutter targeted tests — прошли: Dashboard, responsive 320/768/1440, refetch/reconnect/manual refresh, guest ID, ListingDetail rebuild/reopen/admin exclusion, chat socket, startup/resume, wallet dashboard, guest auth prompt, chat message model.
- 1 Web-тест в Chrome — прошёл: постоянный UUID в настоящем localStorage, повторные/параллельные чтения.
- `flutter analyze --no-version-check` — No issues found; `git diff --check` — прошёл.

## Файлы этой задачи

В рабочей копии до начала задачи уже были изменения auth, seller levels, promotions и другие. Они не относятся к этой доработке. Ниже только файлы, к которым эта задача добавила изменения:

- `backend/apps/api/src/app.module.ts`
- `backend/apps/api/src/modules/usage-analytics/analytics-signal.ts`
- `backend/apps/api/src/modules/usage-analytics/usage-analytics.module.ts`
- `backend/apps/api/src/modules/usage-analytics/usage-analytics.controller.ts`
- `backend/apps/api/src/modules/usage-analytics/usage-analytics.service.ts`
- `backend/apps/api/src/modules/usage-analytics/usage-analytics.spec.ts`
- `backend/apps/api/src/modules/usage-analytics/usage-analytics.postgres.spec.ts`
- `backend/apps/api/src/modules/chats/chats.gateway.ts`
- `backend/apps/api/src/modules/chats/chats.service.ts`
- `backend/apps/api/src/modules/chats/chats.service.spec.ts`
- `backend/dist/tsconfig.tsbuildinfo` (служебные метаданные компилятора)
- `backend/prisma/schema.prisma`
- `backend/prisma/migrations/20260922160000_usage_analytics/migration.sql`
- `lib/src/app.dart`
- `lib/src/features/admin/admin_screen.dart`
- `lib/src/features/admin/admin_usage_analytics.dart`
- `lib/src/features/admin/admin_blocks_screen.dart`
- `lib/src/features/admin/admin_promotions_screen.dart`
- `lib/src/features/admin/admin_reports_screen.dart`
- `lib/src/features/listings/listing_detail_screen.dart`
- `lib/src/services/usage_analytics_service.dart`
- `lib/src/services/chat_socket_service.dart`
- `lib/src/services/web_viewer_device_id.dart`
- `test/features/admin/admin_usage_analytics_test.dart`
- `test/features/listings/listing_detail_screen_test.dart`
- `test/services/usage_analytics_service_test.dart`
- `test/services/guest_identifier_web_test.dart`
- `docs/admin-usage-analytics.md`
