# Bakaláři password removal

Prepared on 7 September 2026; production database cleanup verified on 8 September 2026 at 04:53:39 UTC (06:53:39 Prague time). The password storage/read boundary is deployed. The cleanup scanned all 198 encrypted records, rewrote 12, and then verified `needing_cleanup: 0` across all 198. All 27 school links and 5 push registrations remain intact. See [the production cleanup record](PasswordCleanup-2026-09-08.md).

The updated app and the four application Edge Functions have not been released/deployed by this work. Existing endpoint versions can still receive legacy request bodies; the database now removes password fields before encryption. The published policy has not been changed. Historical backup/PITR, log and export retention remains unverified.

## Behavior in this checkout

- The app keeps school credentials in device-only Keychain storage. It sends the password directly to the school's HTTPS login endpoint. Apple Watch may receive school credentials through the existing paired-device sync and keep its own device-only Keychain copy.
- Linking or reconnecting a Bakaláři account performs a second direct school login on the device. Only that separate access/refresh token family is uploaded for background mark checks. The device retains its original tokens. A failed second login never falls back to sending the password or the device's refresh token.
- Gradey still stores sensitive school access and refresh tokens, school URLs, account identifiers, and the school data needed by the existing cloud features. Removing passwords does not remove all backend access to school data.
- The poller uses tokens only. Revoked/expired refresh tokens need reconnect; the existing app recovery flow can reconnect directly to school using its local Keychain credentials.
- A new device, or an account without a matching local session, needs school sign-in. Cloud activation never returns or adopts the poller's rotating refresh token. Existing local sessions continue to work.
- Updated link/relink endpoints reject requests without the token-only protocol header before parsing the body. They reject any password fields and require a dedicated polling session. Older app versions must update to link/reconnect. Old clients can still transmit a legacy HTTP body before rejection; do not claim that the network can never receive a password from an old or third-party client.
- An allowlist protects all four encrypted writers and the read RPC. Bakaláři username/password objects and other unexpected fields are removed. EduPage session context, Strava.cz session fields, and APNs tokens retain their existing supported fields.

## Remaining app and function rollout

1. Production project `ieonvnfzkbyybbkfxupq` has been verified. Although project discovery returned an empty list and the CLI remained unauthorized, the connector's project-specific operations worked. Four existing database function bodies matched the reviewed definitions. Recheck deployed application functions for drift before their later rollout.
2. Prepare the updated app release and communicate that older versions need to update to link or reconnect. Run a controlled school-account check: device login, cloud link, background mark fetch/refresh, device refresh, reconnect, and new-device sign-in. Local tests use synthetic credentials; a live school token family has not been exercised here.
3. Migration `20260908045010_provider_password_boundary.sql` is already applied. Coordinate the later app release with deployment of `link-school-account`, `relink-school-account`, `activate-school-account`, and `poll-new-marks`, including their shared dependencies. Preserve each function's JWT configuration and notification delivery. The currently deployed marks poller uses access tokens only and has no password-login or refresh-token code, so no polling cutover was needed for this database cleanup.
4. The historical cleanup is complete. If a future restore or migration requires another check, the cleanup script can run in dry-run mode using securely supplied `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `PROVIDER_SECRET_KEY`. It returns only aggregate counts and covers inactive and orphaned records.

   ```sh
   deno run --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,PROVIDER_SECRET_KEY --allow-net Scripts/purge-provider-passwords.ts
   ```

5. The user explicitly authorized removal, and apply plus verification succeeded on 8 September. For an authorized future cleanup, `--apply` re-encrypts sanitized payloads and automatically verifies the result. Require a successful exit and `needing_cleanup: 0`; a changed reader alone is not evidence of stored-data removal. The operation locks rows during its transaction.
6. Confirm deployed old-client rejection, password-free activation, token-only polling and correct recovery behavior. Check aggregate account/poll health without dumping decrypted payloads. Run the Supabase security advisors after deployment.
7. Verify actual backup/PITR and log retention with the project configuration before making a deletion claim. The purge rewrites the active database; it does not immediately erase old backups, WAL/PITR history, exports, or any previously collected logs. Do not invent a retention period. Keep a record of cleanup time, aggregate verification, and the confirmed retention window. Review logging to ensure request bodies and provider secrets are not captured.
8. Publish coordinated English and Czech policy changes only when the app/backend rollout is verified. Set the real effective date and release version at publication. App Store privacy disclosures should describe remaining tokens and school data accurately.

## Proposed English policy text

Draft replacements for the [published English policy](https://help.bukovinafilip.com/en/articles/10-privacy-policy), reviewed on 7 September 2026. These are targeted technical corrections, not a replacement for the entire policy.

### Replace section 3.2

**3.2 Linked school accounts and school sign-in**

Gradey is an unofficial client. You may connect a school or canteen account to view its data in the app. Connect an account only if you are authorised to use it.

In the updated version of Gradey, your Bakaláři username and password are used on your device to sign in directly to your school's HTTPS server. The password is not included in requests that the updated app sends to Gradey's backend. The app keeps your school credentials in device-only Keychain storage so it can sign in to the school again when needed. If you use Apple Watch, the paired-device transfer described in section 3.4 also applies.

When you link a Bakaláři account to Gradey ID, the app obtains a separate school session for background mark checks. Gradey's backend stores that session's access and refresh tokens in encrypted form, together with the school's URL, account identifiers and the school data needed for these features. Tokens are sensitive: they can authorise access to your school data while valid. Our backend renews this session with a refresh token and does not use a school password to sign in. If the session cannot be renewed, reconnect the school account in Gradey. Signing in on another device also requires school sign-in on that device.

Older app versions may attempt to send the previous password-containing request. Updated backend endpoints reject that request; users must update the app to link or reconnect a school account. The previous handling of stored passwords and its retention limits are described in section 7.

For EduPage, the backend receives session identifiers, the username, the gsec hash and student/subject context used by the supported school features. The EduPage password remains in local device storage. For Strava.cz, Gradey uses local credentials to sign in to the canteen service; the backend receives session and canteen/account identifiers, without the password.

### Related edits

- Section 3.3, final paragraph: “We use school data to display the features you request in the app, widgets and Apple Watch. Background cloud checks retrieve marks and maintain the associated grade history and notifications. Timetable and absence data are retrieved by the device. If you opt in to Gradey AI, relevant school context may also be used as described below.”
- Section 4, contract-purpose wording: replace the school-credential-upload purpose with “linking school accounts using session tokens and checking for new marks in the background”. Preserve the rest of the existing legal-basis discussion pending its normal review.
- Section 5, Supabase entry: “Supabase — Gradey ID, linked-account records, encrypted school session tokens, push tokens, and school data used for background mark checks, history and notifications.”
- Section 7: describe current backend retention in terms of session tokens and school data. Add a truthful transition note after verified cleanup: “Earlier versions uploaded Bakaláři passwords. On [verified cleanup date], we removed the password fields from the active backend database. Copies in historical backups or other retained records are subject to [verified retention details].” Do not publish this sentence before cleanup or while either placeholder remains unresolved.
- Section 10, final paragraph: “School session tokens can provide access to school data while valid. Protect your Gradey ID and device passcodes, including your Apple Watch, and sign out on devices you no longer use. Your school password is used directly between your device and the school; it is not part of the updated app's Gradey backend payload.”

## Navržené české znění

Návrh pro [české zásady ochrany osobních údajů](https://help.bukovinafilip.com/cs/articles/10-privacy-policy). Zveřejnit až po ověřeném nasazení; datum účinnosti a informace o uchování záloh musí odpovídat skutečnosti.

### Náhrada oddílu 3.2

**3.2 Propojené školní účty a přihlášení ke škole**

Gradey je neoficiální klient. Školní účet nebo účet jídelny můžete připojit, abyste v aplikaci zobrazili jeho data. Připojujte pouze účty, které jste oprávněni používat.

V aktualizované verzi Gradey se vaše uživatelské jméno a heslo do Bakalářů používají na vašem zařízení k přímému přihlášení k HTTPS serveru školy. Heslo není součástí požadavků, které aktualizovaná aplikace posílá na servery Gradey. Aplikace uchovává školní přihlašovací údaje v Klíčence v režimu vázaném na dané zařízení, aby se v případě potřeby mohla znovu přihlásit ke škole. Používáte-li Apple Watch, platí také přenos mezi spárovanými zařízeními popsaný v oddílu 3.4.

Při propojení účtu Bakalářů s Gradey ID získá aplikace samostatnou školní relaci pro kontrolu nových známek na pozadí. Servery Gradey uchovávají přístupový a obnovovací token této relace v šifrované podobě společně s adresou školy, identifikátory účtu a školními daty potřebnými pro tyto funkce. Tokeny jsou citlivé údaje: po dobu své platnosti mohou umožňovat přístup ke školním datům. Server obnovuje relaci pomocí obnovovacího tokenu a nepřihlašuje se školním heslem. Pokud relaci nelze obnovit, připojte školní účet v Gradey znovu. Přihlášení na jiném zařízení také vyžaduje přihlášení ke škole na tomto zařízení.

Starší verze aplikace se mohou pokusit odeslat původní požadavek obsahující heslo. Aktualizované servery tento požadavek odmítnou; pro propojení nebo opětovné připojení účtu je nutné aplikaci aktualizovat. Předchozí zpracování uložených hesel a omezení jejich uchování popisuje oddíl 7.

U EduPage server přijímá identifikátory relace, uživatelské jméno, hash gsec a údaje o žákovi a předmětech potřebné pro podporované školní funkce. Heslo do EduPage zůstává v místním úložišti zařízení. U Strava.cz používá Gradey místní přihlašovací údaje pro přihlášení ke službě jídelny; server přijímá identifikátory relace, jídelny a účtu bez hesla.

### Související úpravy

- Oddíl 3.3: „Školní data používáme k zobrazení požadovaných funkcí v aplikaci, widgetech a na Apple Watch. Serverové kontroly na pozadí načítají známky a zajišťují související historii a oznámení. Rozvrh a absence načítá zařízení. Pokud povolíte Gradey AI, může se použít také související školní kontext podle níže uvedených pravidel.“
- Oddíl 4: účel nahrávání školních hesel nahraďte textem „propojení školních účtů pomocí tokenů relace a kontrola nových známek na pozadí“. Ostatní text o právních základech ponechte k běžné revizi.
- Oddíl 5, Supabase: „Supabase — Gradey ID, záznamy o propojených účtech, šifrované tokeny školních relací, tokeny pro doručování oznámení a školní data používaná pro kontrolu známek na pozadí, historii a oznámení.“
- Oddíl 7, až po ověřeném odstranění: „Dřívější verze nahrávaly hesla do Bakalářů. Dne [ověřené datum odstranění] jsme pole s hesly odstranili z aktivní serverové databáze. Kopie v historických zálohách nebo jiných uchovávaných záznamech podléhají [ověřené podmínky uchování].“ Nezveřejňujte před provedením a ověřením odstranění ani s nevyplněnými údaji.
- Oddíl 10: „Tokeny školních relací mohou po dobu své platnosti umožňovat přístup ke školním datům. Chraňte svůj Gradey ID a přístupové kódy zařízení včetně Apple Watch a odhlaste se ze zařízení, která již nepoužíváte. Školní heslo se používá přímo mezi vaším zařízením a školou; není součástí dat, která aktualizovaná aplikace posílá na servery Gradey.“

## Verification

- Backend: **43 shared Deno tests passed**. Type checks passed for the four changed Edge Functions and the cleanup script. The cleanup script also refused to run without the required environment configuration.
- Database: `supabase/tests/provider_password_boundary.sql` runs against real PostgreSQL and pgcrypto in an isolated local fixture. It exercises all encrypted writers, filtered legacy reads, service-role execution, dry-run/apply/idempotent cleanup, inactive/orphan handling, ownership, APNs/canteen/EduPage preservation and function permissions. Cron functions in the fixture do not schedule network activity.
- App: **85 tests passed** across `ProviderPasswordPrivacyTests`, `GradeyPlatformTests`, and `GradelyTests` on an iPhone 17 simulator (iOS 26.5). They cover actual encoded link/relink requests, device/cloud token separation, missing credentials, failed school login, legacy activation decoding, existing local sessions and new-device bootstrap. Simulator tests ran without opening the Simulator UI. Final result: `/tmp/GradeyPrivacyTests-20260907-final.xcresult`.
- Production database cleanup and permissions are verified; the complete app/Edge Function rollout, backup retention and real-school behavior still require the remaining checks above.
- Local SQL verification installed Homebrew PostgreSQL 17 and its dependencies. No login/background service was enabled; the temporary database process is stopped. The test simulator is also shut down. Synthetic database fixtures and test logs remain under `/tmp/gradey-privacy-db-20260907` and `/tmp/gradey-privacy-*` for review.

References: [Supabase function privileges](https://supabase.com/docs/guides/database/functions) and [backup/PITR behavior](https://supabase.com/docs/guides/platform/backups).
