-- READ-ONLY preflight for 20261109120000_email_passwordless_auth.
-- Run before prisma migrate deploy. Every statement is SELECT-only.

BEGIN TRANSACTION READ ONLY;

SELECT
  MD5(LOWER(BTRIM(email))) AS normalized_email_fingerprint,
  COUNT(*)::bigint AS account_count
FROM users
WHERE email IS NOT NULL
GROUP BY LOWER(BTRIM(email))
HAVING COUNT(*) > 1
ORDER BY account_count DESC, normalized_email_fingerprint;

SELECT
  COUNT(*)::bigint AS duplicate_normalized_email_groups,
  COALESCE(SUM(account_count), 0)::bigint AS accounts_in_duplicate_groups
FROM (
  SELECT COUNT(*)::bigint AS account_count
  FROM users
  WHERE email IS NOT NULL
  GROUP BY LOWER(BTRIM(email))
  HAVING COUNT(*) > 1
) duplicates;

COMMIT;
