ALTER TABLE "user_devices"
ADD COLUMN "supports_android_data_only_push" BOOLEAN;

CREATE TABLE "admin_push_deliveries" (
  "id" UUID NOT NULL,
  "notification_id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "device_id" UUID NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "next_attempt_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "locked_until" TIMESTAMP(3),
  "last_error" TEXT,
  "delivered_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "admin_push_deliveries_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "admin_push_deliveries_notification_id_fkey"
    FOREIGN KEY ("notification_id") REFERENCES "user_notifications"("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "admin_push_deliveries_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "admin_push_deliveries_device_id_fkey"
    FOREIGN KEY ("device_id") REFERENCES "user_devices"("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "admin_push_deliveries_notification_id_device_id_key"
ON "admin_push_deliveries"("notification_id", "device_id");

CREATE INDEX "admin_push_deliveries_status_next_attempt_at_locked_until_idx"
ON "admin_push_deliveries"("status", "next_attempt_at", "locked_until");

CREATE INDEX "admin_push_deliveries_user_id_created_at_idx"
ON "admin_push_deliveries"("user_id", "created_at");
