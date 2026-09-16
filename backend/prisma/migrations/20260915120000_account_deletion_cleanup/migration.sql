-- CreateTable
CREATE TABLE "account_deletion_cleanup" (
    "user_id" UUID NOT NULL,
    "avatar_urls" TEXT[],
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "retry_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "account_deletion_cleanup_pkey" PRIMARY KEY ("user_id")
);

-- CreateIndex
CREATE INDEX "account_deletion_cleanup_retry_at_idx" ON "account_deletion_cleanup"("retry_at");

