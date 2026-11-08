ALTER TABLE "payments" ADD COLUMN "refunded_amount_rub" DECIMAL(12,2) NOT NULL DEFAULT 0;
ALTER TABLE "payments" ADD COLUMN "is_test" BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE "raffle_snapshots" (
  "id" UUID NOT NULL,
  "from" TIMESTAMPTZ(3) NOT NULL,
  "to" TIMESTAMPTZ(3) NOT NULL,
  "ticket_price_rub" DECIMAL(12,2) NOT NULL,
  "participants_count" INTEGER NOT NULL,
  "tickets_count" BIGINT NOT NULL,
  "amount_rub" DECIMAL(18,2) NOT NULL,
  "fingerprint" TEXT NOT NULL,
  "created_by_id" UUID NOT NULL,
  "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "raffle_snapshots_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "raffle_snapshot_participants" (
  "id" UUID NOT NULL,
  "snapshot_id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "phone" TEXT NOT NULL,
  "total_rub" DECIMAL(18,2) NOT NULL,
  "tickets" BIGINT NOT NULL,
  "remainder_rub" DECIMAL(18,2) NOT NULL,
  "first_at" TIMESTAMPTZ(3) NOT NULL,
  "last_at" TIMESTAMPTZ(3) NOT NULL,
  "first_ticket" BIGINT NOT NULL,
  "last_ticket" BIGINT NOT NULL,
  CONSTRAINT "raffle_snapshot_participants_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "raffle_snapshots_fingerprint_key" ON "raffle_snapshots"("fingerprint");
CREATE INDEX "raffle_snapshots_created_at_idx" ON "raffle_snapshots"("created_at");
CREATE UNIQUE INDEX "raffle_snapshot_participants_snapshot_id_user_id_key" ON "raffle_snapshot_participants"("snapshot_id", "user_id");
CREATE INDEX "raffle_snapshot_participants_snapshot_id_first_ticket_last_ticket_idx" ON "raffle_snapshot_participants"("snapshot_id", "first_ticket", "last_ticket");
ALTER TABLE "raffle_snapshots" ADD CONSTRAINT "raffle_snapshots_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "raffle_snapshot_participants" ADD CONSTRAINT "raffle_snapshot_participants_snapshot_id_fkey" FOREIGN KEY ("snapshot_id") REFERENCES "raffle_snapshots"("id") ON DELETE CASCADE ON UPDATE CASCADE;
