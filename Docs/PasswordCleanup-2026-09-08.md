# Production Bakaláři password cleanup

Completed on 8 September 2026 at **04:53:39.100 UTC / 06:53:39.100 Europe/Prague**, following the user's explicit instruction to delete the stored passwords.

## Verified scope and outcome

Project: `ieonvnfzkbyybbkfxupq`, OpenSide, `filip@bukovinafilip.com's Project`, production branch, eu-central-1.

| Check | Result |
| --- | ---: |
| Encrypted records scanned before cleanup | 198 |
| Records needing sanitization | 12 |
| Records re-encrypted by apply | 12 |
| Records scanned by post-apply verification | 198 |
| Records still needing cleanup | **0** |
| School links after cleanup | 27 |
| Push registrations after cleanup | 5 |
| Broken school/push secret references | 0 / 0 |

The scan covered `public.encrypted_provider_secrets`, including the 166 records that had no current school-link or push-registration reference. It decrypted values inside Supabase, removed fields outside the reviewed session-data allowlist, and re-encrypted changed records. It preserved record IDs, ownership, supported session-token fields and linked records. No decrypted passwords or provider encryption keys were returned to the operator.

## Deployed protection

Migration `20260908045010_provider_password_boundary.sql` sanitizes every encrypted writer and the read RPC. The four pre-existing function bodies were checked against the reviewed source before replacement. The live database lacked `update_provider_secret`; the migration creates it with explicit service-role-only execution permissions. This older-schema path was tested locally with PostgreSQL 17 and pgcrypto before deployment.

All six relevant RPCs were checked after deployment: anonymous and authenticated app users cannot execute them; `service_role` can. Both existing cron jobs remain active. The deployed marks poller was inspected and uses access tokens only; it has no password-login or refresh-token branch. It was not replaced during this operation.

The temporary `purge-provider-passwords` Edge Function used a private, short-lived operator authorization token. It rejected an unauthenticated apply request with HTTP 401. Dry-run and apply returned aggregate counts only. After successful verification, version 3 replaced all maintenance code with an inert HTTP 410 response and enabled gateway JWT verification; an unauthenticated invocation was again rejected with HTTP 401. The temporary local operator token was removed. The retired function entry may remain in the dashboard, but its deployed code cannot access or modify the database.

## Verification and limits

- Real PostgreSQL/pgcrypto integration checks passed for encrypted writers, sanitization, account preservation, service-role permissions, dry-run/apply behavior and idempotence, including the previously absent refresh writer.
- Temporary handler checks passed for missing/wrong authorization, explicit operation mode, aggregate-only output, redacted errors and apply followed by verification.
- Supabase security advisors reported no new database privilege warning. Existing findings concern intentionally closed RLS tables without client policies, Auth leaked-password protection, and MFA configuration. Those unrelated settings were not changed. References: [RLS advisory](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), [MFA](https://supabase.com/docs/guides/auth/auth-mfa).
- This proves removal from current, visible encrypted provider records. Historical backups, WAL/PITR, old storage versions, logs and exports were not inspected or erased. Do not claim physical erasure from every retained copy or invent a retention period.
- The app and the four application Edge Functions prepared on 7 September are still pending release. Existing apps can still send legacy request bodies to existing endpoints; the database now strips password fields before storing them. Do not yet claim that all deployed clients have stopped transmitting passwords.
- The full privacy-policy draft now includes the verified cleanup date. Its publication note and backup-retention placeholder still need resolution before publication.
