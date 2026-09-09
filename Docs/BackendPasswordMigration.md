# Bakaláři password migration

Gradey 2.1 removes Bakaláři passwords from the app's school-linking requests. The device authenticates directly with the school and establishes a separate token session for backend mark polling. Access and refresh tokens still grant access to school data and remain sensitive. This change does not remove school passwords from the device's Keychain or change the password at the school.

## Backend changes in this release

- `link-school-account` and `relink-school-account` require the `x-gradey-provider-session: tokens-only-v1` header before parsing the request body, reject password fields, and require a separately established polling session.
- `activate-school-account` does not return the backend poller's refresh token to another device. That device signs in directly to the school.
- `poll-new-marks` refreshes its separate token session and requires reconnection when it cannot renew it. There is no password sign-in fallback.
- Migration `20260908045010_provider_password_boundary.sql` sanitizes encrypted provider-secret writes and reads. It preserves supported tokens and APNs device secrets, and restricts the secret functions to the service role.
- `Scripts/purge-provider-passwords.ts` invokes the migration's cleanup function. It defaults to a dry run and prints aggregate counts only. Applying it rewrites affected encrypted records while preserving their IDs and references.

## Rollout and verification

Publishing a GitHub release does not deploy Edge Functions, migrate a database, or update the hosted privacy policy. Verify each environment separately.

1. Apply the database migration and verify the service-role-only function grants.
2. Run the cleanup script in dry-run mode with `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `PROVIDER_SECRET_KEY` supplied securely through the operator environment. Never put these values in source control, command history, or logs.
3. Run the script with `--apply` to remove legacy password fields from existing encrypted records. The script immediately performs another dry run and fails if any records still need cleanup. Verify that linked-account and push-token references remain intact.
4. Coordinate deployment of the four Edge Functions with the updated client. Older clients that send credentials do not satisfy the new endpoint contract and need an update. Test linking, reconnecting, activation on another device, token refresh, expired-token handling, and background notifications with a dedicated test account.
5. Align the hosted privacy policy, its effective date, the in-app revision, and App Store disclosures with the deployed behavior before distributing the app.

The cleanup verifies the active encrypted-secret table. Historical backups, point-in-time recovery data, logs, and exports have separate retention paths and must be assessed before making broader deletion claims. Restoring an older backup also requires reapplying the password boundary and cleanup before resuming service.

The in-app privacy effective date is provisional until the corresponding policy is published. Keep production audit records and credentials outside this public repository.
