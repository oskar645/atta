# Passwordless authentication

This additive API uses the existing SMS.ru CallCheck, PhoneVerification, auth
response, UserSession and refresh implementation. No Prisma migration is needed.
Legacy password, phone, email and restore-credentials routes remain available.

## Contract

- `POST /auth/passwordless/start`: `{ "phone": "8 (999) 123-45-67" }`.
  Returns `{ status: "pending", challenge, callToPhone, expiresAt, ttlSeconds }`.
  Phone normalization and provider behavior are shared with `/auth/phone/start`.
  It never queries User or BlockedIdentity. Challenge TTL is at most 5 minutes.
- `POST /auth/passwordless/check`: `{ "challenge": "<opaque value>" }`.
  Pending/failed/expired CallCheck results use the existing phone status response.
  Once confirmed, an eligible existing account receives the standard
  `{ user, admin_profile, is_admin, isAdmin, auth }` response with its original ID.
  An unknown phone receives `{ status: "registration_required", registrationToken,
  expiresAt, ttlSeconds }`. Registration TTL is at most 3 minutes and never exceeds
  the original challenge expiry.
- `POST /auth/passwordless/complete`: `{ "registrationToken": "<opaque value>",
  "displayName": "Name", "acceptedLegal": true, "acceptedPersonalData": true }`.
  Optional fields: `acceptedMarketing` (defaults to false), `platform`
  (`IOS`, `ANDROID`, `WEB`), `legalDocumentVersion` (must match the current server
  version when supplied). Consent records always use the same server version as
  legacy signup. Returns the standard auth response immediately.

Check/complete do not accept a phone. Global DTO validation rejects extra fields.
No endpoint accepts a provider verification ID as a passwordless credential.
The client must treat challenge/token values as opaque secrets.

## Retries and atomicity

Challenge and registration secrets contain 32 random bytes. Only SHA-256 hashes
are stored in `PhoneVerification.metadata.passwordless`; purpose is `LOGIN`.
The new account's required passwordHash is bcrypt over a separate random
32-byte secret that is never returned or logged.

PostgreSQL row locks serialize polling and transitions, including across API
processes. Complete additionally takes a transaction-scoped phone advisory lock.
User, consents, wallet/signup bonus, session and token consumption commit together.
A User.phone unique conflict with legacy signup rolls back the transaction and
rechecks the winning account's access restrictions in a fresh transaction.
Existing account signup data and bonuses are not rewritten.

Successful check/complete consumes its input credential and stores the resulting
passwordless response on the challenge until the challenge expires. Replay before
expiry returns the same registration/auth response without minting another
session, recreating the account, or repeating signup rewards. Invalid/expired
credentials return `400 PASSWORDLESS_INVALID`. A failed transaction leaves the
credential retryable until its TTL expires.

## Limits and operational bounds

RateLimitService applies start 1/minute/normalized phone; check 20/minute/challenge;
complete 6/minute/token's verification ID. Source limits are 10/minute/IP and
device for start/complete and 60/minute for check, separately per action.
Passwordless polling is valid until the five-minute challenge TTL or a terminal
provider result, with no attempt-count failure. The legacy phone flow retains
its five-attempt limit. A five-second cooldown after each pending provider poll
is stored in challenge metadata under the PostgreSQL row lock; early checks
return `pending`, `retryAfterSeconds`, and `Retry-After` without calling SMS.ru.
Concurrent checks, including across API processes, share that lock and cooldown.
Provider outages and unexpected status payloads also commit a pending cooldown;
they do not invalidate the challenge. SMS.ru documents 400 (pending), 401
(confirmed), and 402 (expired or invalid provider ID) for CallCheck.
Requests use the configured trusted-proxy `request.ip`, not a raw forwarded
header. `429` includes a conservative `Retry-After: 60`; all responses use
`Cache-Control: no-store`.

RateLimitService retains its existing process-local fallback if Redis fails;
distributed rate limits therefore depend on Redis availability. Database locks
still protect one-time consumption and polling. Provider polling holds a DB
transaction, bounded by the existing 10-second provider timeout and a 20-second
transaction timeout. Production SMS.ru was not called by the tests.

Desktop Web uses the same flow: display the user's phone and CallCheck number,
then poll independently while the user calls manually from that phone's SIM.
Neither a browser `tel:` launch nor a lifecycle resume event is required.
IP/device values are abuse signals, not challenge credentials; Wi-Fi/mobile/VPN
changes and a temporary browser outage do not require another start. Reconnect
must occur before expiry. Existing Flutter controller/widget tests cover polling
without a dialer, an unavailable dialer, automatic login/registration, and network
retries; PostgreSQL tests cover provider confirmation and idempotent responses.
These are simulated-provider checks, not a live two-device SMS.ru call test.

## Tests

Run ordinary tests with `node --test -r ts-node/register/transpile-only` and the
desired `.spec.ts` paths. `passwordless.service.spec.ts` exercises validation,
normalization, rate limits and anti-enumeration without external services.

`passwordless.postgres.spec.ts` additionally exercises real PostgreSQL rollback,
locks, concurrent complete, unique conflicts, replay, TTL, access restrictions,
consents/wallets/bonuses and legacy auth regression. It uses real AuthService,
WalletService, JWT/bcrypt and the CallCheck state code, with a mocked SMS.ru
transport. The URL must be provided explicitly via
`ATTA_PASSWORDLESS_TEST_DATABASE_URL`; there is no DATABASE_URL fallback.
The suite requires an isolated database named `atta_passwordless_regression`,
user `atta_test`, host `localhost`, and a Unix socket under
`/private/tmp/atta-passwordless-pg.<suffix>/socket`. Initialize that empty test
database from the unchanged Prisma schema before running. Tests create synthetic
records and the temporary cluster can be removed afterwards.
