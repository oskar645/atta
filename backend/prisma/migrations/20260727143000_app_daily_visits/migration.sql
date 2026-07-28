CREATE TABLE "app_daily_visits" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "visit_date" DATE NOT NULL,
  "last_activity_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "app_daily_visits_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "app_daily_visits_user_id_visit_date_key"
  ON "app_daily_visits"("user_id", "visit_date");

CREATE INDEX "app_daily_visits_visit_date_last_activity_at_idx"
  ON "app_daily_visits"("visit_date", "last_activity_at");

ALTER TABLE "app_daily_visits"
  ADD CONSTRAINT "app_daily_visits_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
