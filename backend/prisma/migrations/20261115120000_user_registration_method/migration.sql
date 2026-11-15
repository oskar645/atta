CREATE TYPE "RegistrationMethod" AS ENUM ('PHONE', 'EMAIL', 'LEGACY_UNKNOWN');

ALTER TABLE "users"
  ADD COLUMN "registration_method" "RegistrationMethod" NOT NULL DEFAULT 'LEGACY_UNKNOWN';

-- A linked, confirmed SIGNUP verification is direct evidence of the original
-- phone registration flow. Passwordless phone registration uses LOGIN, but is
-- distinguishable from an ordinary login by its registration capability.
WITH phone_registration_evidence AS (
  SELECT
    pv."created_user_id" AS user_id,
    MIN(pv."created_at") AS first_registration_at
  FROM "phone_verifications" pv
  WHERE pv."created_user_id" IS NOT NULL
    AND pv."status" = 'CONFIRMED'
    AND (
      pv."purpose" = 'SIGNUP'
      OR (
        pv."purpose" = 'LOGIN'
        AND pv."metadata" #>> '{passwordless,registrationExpiresAt}' IS NOT NULL
      )
    )
  GROUP BY pv."created_user_id"
),
email_registration_evidence AS (
  SELECT
    (ec."metadata" #>> '{emailPasswordless,authResponse,auth,user_id}')::uuid AS user_id,
    MIN(ec."created_at") AS first_registration_at
  FROM "email_challenges" ec
  WHERE ec."purpose" = 'EMAIL_AUTH'
    AND ec."user_id" IS NULL
    AND ec."consumed_at" IS NOT NULL
    AND ec."metadata" #>> '{emailPasswordless,state}' = 'consumed'
    AND ec."metadata" #>> '{emailPasswordless,authResponse,auth,user_id}'
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
  GROUP BY (ec."metadata" #>> '{emailPasswordless,authResponse,auth,user_id}')::uuid
),
registration_evidence AS (
  SELECT
    u."id" AS user_id,
    CASE
      WHEN pe.first_registration_at IS NOT NULL
        AND ee.first_registration_at IS NOT NULL
        AND pe.first_registration_at <= ee.first_registration_at THEN 'PHONE'::"RegistrationMethod"
      WHEN pe.first_registration_at IS NOT NULL
        AND ee.first_registration_at IS NULL THEN 'PHONE'::"RegistrationMethod"
      WHEN ee.first_registration_at IS NOT NULL THEN 'EMAIL'::"RegistrationMethod"
      ELSE 'LEGACY_UNKNOWN'::"RegistrationMethod"
    END AS registration_method
  FROM "users" u
  LEFT JOIN phone_registration_evidence pe ON pe.user_id = u."id"
  LEFT JOIN email_registration_evidence ee ON ee.user_id = u."id"
)
UPDATE "users" u
SET "registration_method" = evidence.registration_method
FROM registration_evidence evidence
WHERE evidence.user_id = u."id"
  AND evidence.registration_method <> 'LEGACY_UNKNOWN';

CREATE OR REPLACE FUNCTION prevent_user_registration_method_change()
RETURNS trigger AS $$
BEGIN
  IF NEW."registration_method" IS DISTINCT FROM OLD."registration_method" THEN
    RAISE EXCEPTION 'registration_method is immutable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER "users_registration_method_immutable"
BEFORE UPDATE OF "registration_method" ON "users"
FOR EACH ROW
EXECUTE FUNCTION prevent_user_registration_method_change();
