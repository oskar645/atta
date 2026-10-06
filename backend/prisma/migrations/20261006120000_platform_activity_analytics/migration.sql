CREATE TABLE "analytics_platform_activity" (
    "user_id" UUID NOT NULL,
    "platform" "DevicePlatform" NOT NULL,
    "day" DATE NOT NULL,
    "app_version" TEXT NOT NULL DEFAULT '',
    "build_number" TEXT NOT NULL DEFAULT '',
    "last_activity_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "analytics_platform_activity_pkey" PRIMARY KEY ("user_id", "platform", "day"),
    CONSTRAINT "analytics_platform_activity_user_id_fkey"
      FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "analytics_platform_activity_day_platform_idx"
  ON "analytics_platform_activity"("day", "platform");
CREATE INDEX "analytics_platform_activity_platform_app_version_day_idx"
  ON "analytics_platform_activity"("platform", "app_version", "day");
