CREATE TABLE "app_download_daily_stats" (
    "id" UUID NOT NULL,
    "platform" TEXT NOT NULL,
    "report_date" DATE NOT NULL,
    "downloads" INTEGER NOT NULL,
    "source_metric" TEXT NOT NULL,
    "source_time_zone" TEXT NOT NULL,
    "last_synced_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "app_download_daily_stats_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "app_download_daily_stats_platform_report_date_key"
ON "app_download_daily_stats"("platform", "report_date");
