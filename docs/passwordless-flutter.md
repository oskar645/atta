# Flutter passwordless: локальные изменения

GuestAuthSheet открывает единый PasswordlessScreen кнопкой «Войти».
Номер нормализуется существующим RuPhoneInputFormatter/normalizeRuPhoneForApi.
В новом UI нет выбора login/signup, пароля, email или check-registration.

После start отображаются номер для звонка и оставшееся время по expiresAt.
Звонилка только открывает tel:. Её закрытие, отмена или отсутствие tel:-обработчика
не меняют auth state. Polling работает по таймеру, в том числе в Web без resumed.
Check выполняется последовательно: через 5 секунд после предыдущего ответа,
после временной ошибки — через 10 секунд; 429 учитывает Retry-After с fallback 60 секунд.
Сетевая ошибка не вызывает start. Повторяется тот же challenge; complete можно
повторить с тем же registrationToken при потере ответа. После срока действия
новый start выполняется только кнопкой «Попробовать снова».

Existing user: auth response из check проходит через прежний _consumeAuthPayload.
New user: registration_required → имя и два прежних обязательных согласия → complete
→ тот же _consumeAuthPayload. Legal-тексты, документы и ссылки не менялись;
компонент согласий вынесен из старого экрана и используется обоими flow.
Guest prompt возвращает результат исходному действию. На низком Web-окне sheet
прокручивается. Запоздалые ответы после выхода назад/закрытия flow игнорируются;
проверка session generation защищает от восстановления сессии после logout.

AuthGate, startup/session restore, TokenStorage и его ключи, refresh/logout,
Android Restore Credentials не изменены. Старые password UI/API оставлены
для совместимости, но новый guest entry больше на них не ведёт.

## Реальная несовместимость backend, оставленная без изменений

`backend/apps/api/src/modules/phone-verification/phone-verification.service.ts`:
`MAX_CHECK_ATTEMPTS = 5`; каждый pending provider check увеличивает attempts.
Шестой check переводит запись в FAILED, дальнейшие проверки уже не опрашивают
провайдера, хотя expiresAt ещё может быть в будущем.
`PasswordlessService.check()` использует этот механизм напрямую.

При быстрых pending-ответах и интервале 5 секунд лимит исчерпывается примерно
за 30 секунд. Поздний звонок уже не подтвердится, даже если UI продолжает показывать
остаток срока и сохраняет challenge. Отмена звонилки сама по себе ошибкой не считается.

Следовательно, требование надёжного подтверждения в любой момент до expiresAt
нельзя полностью обеспечить текущим backend-контрактом. Требуется отдельно
согласованное изменение политики provider polling для passwordless: pending-проверки
не должны делать живой challenge необратимо непроверяемым; rate limit можно сохранить.
Backend здесь не исправлялся. Flutter-тесты с подставными ответами не доказывают
отсутствие этого ограничения в реальном CallCheck. Настоящие звонки не выполнялись.

## Проверки

Итог: analyze — без замечаний; 136 targeted/regression тестов прошли;
29 тестов в Chrome прошли; git diff --check — без ошибок.

- `flutter analyze --no-version-check`
- `flutter test --no-version-check test/features/auth test/services/backend_auth_service_test.dart test/services/api_client_test.dart test/services/passwordless_auth_test.dart test/app_startup_resume_test.dart test/utils/ru_phone_test.dart`
- `flutter test --no-version-check --platform chrome test/features/auth/passwordless_controller_test.dart test/features/auth/passwordless_screen_test.dart test/features/auth/guest_auth_prompt_test.dart`
- `git diff --check`

Новые тесты покрывают нормализацию, оба flow, consent gating, сохранение прежним
механизмом токенов/пользователя, отмену dialer, отсутствие tel:-обработчика, network/
timeout/503, Retry-After, повтор check/complete, expiry, отсутствие параллельных check,
защиту от двойного нажатия, уход назад, безопасные сообщения блокировки,
возврат к guest action и Web polling без lifecycle events. Существующие startup,
auth/session, Android restore и legacy phone/legal тесты выполняются вместе с ними.

## Файлы, изменённые именно в этой задаче

- `lib/src/features/auth/guest_auth_prompt.dart`
- `lib/src/features/auth/login_screen.dart`
- `lib/src/features/auth/passwordless_controller.dart` — новый
- `lib/src/features/auth/passwordless_screen.dart` — новый
- `lib/src/features/auth/registration_consents.dart` — новый
- `lib/src/services/api/api_client.dart`
- `lib/src/services/api/api_exception.dart`
- `lib/src/services/api/auth_api.dart`
- `lib/src/services/auth_service.dart`
- `lib/src/services/backend_auth_service.dart`
- `test/features/auth/guest_auth_prompt_test.dart`
- `test/features/auth/passwordless_controller_test.dart` — новый
- `test/features/auth/passwordless_screen_test.dart` — новый
- `test/services/passwordless_auth_test.dart` — новый
- `docs/passwordless-flutter.md` — новый

Другие незакоммиченные изменения уже были в рабочей папке до этой задачи.

Flutter изменения: да.
Backend изменения в этой задаче: нет.
Нужно обновить сервер для полноценного нового flow: да, отдельным этапом после
устранения ограничения polling и с доступными passwordless endpoints.
Migration нужна: нет.
Commit/push/deploy: не выполнялись; сборки не публиковались.

### Cold restart resume

Flutter stores one separate `atta_pending_passwordless_v1` JSON record through
`FlutterSecureStorage` (the same platform mechanism as session tokens). It holds
challenge, normalized phone, CallCheck destination, expiry, and, once received,
registration token with its expiry. Existing session keys are unchanged.

After ordinary session initialization, only unauthenticated startup checks for
this record and opens passwordless auth. A live challenge is checked immediately
without a new start; a saved registration token opens name and mandatory consents
without another call. An expired record is deleted and shows phone entry.
Backend check already replays the existing auth response or registration token.
The backend and database schema require no changes for this feature.

Explicit back/cancel/change phone and expiry clear the record. Successful
passwordless login/signup clears it after the normal auth payload consumption.
Widget disposal, process termination, dialer navigation, refresh and network
failures do not clear it. Name drafts and consent checkboxes are not persisted.

Automated restart tests recreate controllers against retained secure-storage
mocks, including confirmation with a lost HTTP response and offline recovery.
Physical Android/iOS process kills and browser refresh/reopen still require
manual device verification using the production platform storage implementation.
