# ATTA production release manifest — 2026-11-08

This manifest describes the current source release candidate only. It does not
authorize a deployment, database change, commit, or modification of production
data.

## Required source groups

- Flutter application sources under `lib/`, matching tests under `test/`, and
  the Android/iOS project metadata changed for the release.
- NestJS sources under `backend/apps/api/src/`, including the new app-download
  module and common realtime signals.
- Prisma schema and every pending migration listed below.
- Backend dependency manifests: `backend/package.json` and
  `backend/package-lock.json`.

## Required pending migrations, in order

1. `20261105120000_index_wallet_promotion_dashboard`
2. `20261105130000_app_download_daily_stats`
3. `20261108120000_support_message_reliability`
4. `20261108130000_admin_push_delivery`
5. `20261108140000_raffle_snapshots`

The last two migrations are additive. Admin push delivery adds an optional
Android capability flag and a durable per-device delivery table; raffle
snapshots add payment classification fields and immutable snapshot tables. Old
application versions remain valid when the capability is `NULL`.

## Explicit exclusions

- `backend/dist/` and `backend/dist/tsconfig.tsbuildinfo`: local generated build
  output; rebuild in an isolated clean directory.
- `backend/node_modules/` and generated Prisma client files: install/generate in
  the release environment.
- `.env*`, signing keys, APNs/FCM credentials, service-account files, logs, and
  other machine-local secrets.
- Root `package-lock.json` and `firepit-log.txt`: unrelated local artifacts.

## Recommended server update order

1. Create a clean release checkout containing only the reviewed source
   manifest; install locked backend dependencies.
2. Validate the Prisma schema and take the normal database backup/checkpoint.
3. Apply the five migrations with `prisma migrate deploy` in the order above.
4. Generate Prisma Client and compile NestJS into an isolated output directory.
5. Restart the API using the existing controlled rollout procedure, then run
   health, authentication, notifications, support, admin dashboard, and export
   smoke checks.
6. Roll out Flutter clients only after the compatible backend is healthy. Old
   Android clients continue receiving legacy notification payloads; new clients
   opt in to data-only delivery at device registration.

## Rollback boundary

Application rollback is safe while the additive columns/tables remain. Do not
drop the new table or capability column during an emergency application
rollback; remove them only in a separately reviewed migration after delivery
records are no longer needed.
