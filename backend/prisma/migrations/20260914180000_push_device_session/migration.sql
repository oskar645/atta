ALTER TABLE "user_devices" ADD COLUMN "session_id" UUID;
-- Legacy tokens have no provable session owner. Re-register on app login/start.
UPDATE "user_devices" SET "is_active" = false WHERE "is_active" = true;
ALTER TABLE "user_devices" ADD CONSTRAINT "user_devices_session_id_fkey"
  FOREIGN KEY ("session_id") REFERENCES "user_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;
