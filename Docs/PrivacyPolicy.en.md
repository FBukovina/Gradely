# Privacy Policy

**Gradey 2.2 draft — publication and effective date must be confirmed before rollout.**

This release source updates the policy published on 9 September 2026. It has not been published by this implementation task.

This revision describes the privacy changes for Gradey 2.1 and the transition from older app versions. The active-database password cleanup described below was already completed on 8 September 2026. Features described for version 2.1 apply when you install that version.

This Privacy Policy explains how **Open Side**, operated by **Filip Bukovina** ("we", "us" or "our"), processes personal data through **Gradey** and its related services.

Gradey is an unofficial school-system client for students and parents. It is available on supported Apple devices, including iPhone, iPad, Apple Watch and Mac, with companion widgets. Gradey is independent of Bakaláři, EduPage and Strava.cz; those organisations do not operate or endorse the app.

## 1. Who is responsible for your data

The controller is **Filip Bukovina**, publishing Gradey as **OpenSide** at [openside.tech](https://openside.tech).

- Privacy requests: **filip@openside.tech**
- Additional contact: **tom@openside.tech**

## 2. What this policy covers

This policy covers Gradey ID, connected school and canteen accounts, school-data features, Apple Watch and widgets, the personal Planner and optional Calendar export, Gradey AI, support, purchases and notifications.

It does not replace the policies of your school, the official school or canteen systems, or services you use independently of Gradey.

## 3. Data we process

### 3.1 Gradey ID

Gradey ID uses Sign in with Apple. Depending on your choices and what Apple provides, we receive an account identifier, your name and your email address or Apple's private relay address.

Our account backend, hosted by Supabase, stores your Gradey account, linked-account records and preferences. It supports account settings, data export and account deletion.

### 3.2 Bakaláři accounts and passwords

**In Gradey 2.1, school sign-in, linking and reconnecting do not upload your Bakaláři password to Gradey's backend.** Older versions are addressed below.

For direct school sign-in, your device sends your school username and password to your school's HTTPS server. Gradey keeps these credentials in the device's Keychain so it can sign in directly to the school again when needed. The Apple Watch behaviour described in section 3.4 also applies.

When you link a Bakaláři account to Gradey ID, our backend processes:

- The URL of your school's server.
- Your username, account identifiers and display information, such as your name and school name.
- School-session access and refresh tokens, with related expiry information.
- School data used for the cloud features described below.

Gradey 2.1 establishes a separate school-token session for background mark checks. **Session tokens are sensitive information: they can allow access to your school data while valid.** We store backend session tokens in encrypted form. Our background service uses session tokens to check for new marks; where supported, a refresh token can renew that access. It does not sign in using a stored school password.

If the background session no longer works, reconnect your school account in Gradey. A device without its own local school session also needs school sign-in.

**Transition from older versions:** Older installed app versions can still send a password in a school-linking or reconnecting request while the rollout is in progress. Since 8 September 2026, database writes remove password fields before storing encrypted provider records. This storage protection does not mean that an older app never transmits a password to the backend. To avoid that legacy transmission, update to Gradey 2.1 before linking or reconnecting. Historical password records and backup limitations are described in section 7.

Only connect accounts you are authorised to use. This protection concerns school-sign-in requests; do not include passwords in AI chats, support messages or attachments, where they would become part of the content you submit.

### 3.3 Other connected accounts and school data

For EduPage, Gradey uses locally stored credentials to sign in. The backend receives session identifiers, a username, authentication hashes and student/subject information needed by supported features, without the EduPage password.

For Strava.cz, Gradey uses local credentials to sign in to the canteen service. Linked-account data sent to our backend includes session, service, canteen and account identifiers, without the password.

Depending on your school and the features you use, Gradey processes names, class information, marks, subjects, absences, timetables, teacher and room information, and canteen or meal data.

The device retrieves timetable and absence data. Background cloud checks retrieve marks and maintain related grade history and notifications. School information may also appear in local caches, widgets and Apple Watch, or be included in optional Gradey AI context as described below.

### 3.4 Apple Watch and widgets

The iPhone can transfer school data and authentication information to a paired Apple Watch, including school credentials, so the Watch can refresh data directly from the school. The Watch may therefore hold its own local copy of your school password and session tokens.

Widgets use locally shared data to display their supported features. Protect your device passcodes, and sign out or unpair devices before giving them to someone else.

### 3.5 Gradey AI

Gradey AI is optional and asks for separate in-app consent. Using AI is not required to view marks, timetables or absences.

When you use it, we process your messages and conversation history for that conversation. General chat does not automatically attach your school record. You can select a subject, a week, study priorities or a specific test; only the selected academic summaries, recent grades, lessons and eligible Planner titles and dates are shared. Planner notes are excluded unless you explicitly choose to include the selected test’s notes. Credentials, school URLs, teacher names and Calendar identifiers are excluded from this automatically selected context.

The selected information is sent through our AI backend, hosted using Google Firebase, to Microsoft Azure OpenAI to generate the response. You can inspect the selected context before sending. Local calculations, simulations and Today insights do not require AI or share their content with an AI provider. A material change to the AI processor requires renewed in-app AI consent.

AI-related processing also includes authentication identifiers, consent status, request and usage information, and verified subscription status where needed to apply daily Compute allowances. A short-lived Gradey ID access token is verified by the backend to connect usage across devices; it is not included in model prompts or stored in the Compute ledger. RevenueCat entitlement verification determines the applicable service allowance. Accounting records include request identifiers, prices, reservations, settlement outcomes and provider costs, without storing another school-context archive for recovery. Conversations can be retained so you can return to them. Use the available conversation-deletion and consent controls, or contact us about removal.

Only submit information you are authorised to share. AI responses can be inaccurate. Withdrawing AI consent does not itself delete your Gradey ID.

### 3.6 In-app support

Gradey uses Intercom for support on supported platforms. After the app's age-confirmation step, an unidentified support session may start before you send a message. "Unidentified" does not mean that no technical data is processed.

If you contact support, Intercom and we may process your messages, contact details you provide, technical device/app information and attachments you choose to send. Camera, microphone or photo access is optional and depends on the attachment you select. You can write to support without granting those permissions.

### 3.7 Purchases

Apple processes payments for tips and support subscriptions. RevenueCat processes purchase and entitlement information so Gradey can recognise support status and apply relevant benefits or usage limits.

We do not receive your full payment-card details or Apple ID password through these purchases. Purchase and subscription management is also subject to Apple's terms.

### 3.8 Notifications

If you enable push notifications, our backend processes a device push token, device-registration details and your notification preferences. These allow us to send updates such as new-mark alerts. The content shown on your lock screen depends on your selected detail settings.

You can change notification preferences in Gradey and system settings. Turning off notifications in system settings controls what the device displays; it does not necessarily delete the backend token immediately. Uninstalling the app is also not an account-deletion request.

### 3.9 Operational and security information

Gradey uses Firebase authentication, backend functions and App Check to support AI access and protect requests. Our hosting and service providers may process technical connection information, app/device information, request timestamps, errors and security signals to operate and protect the service.

We do not sell your personal data or use third-party advertising networks in Gradey.

### 3.10 Personal Planner and Calendar

Personal Planner items, including titles, notes, dates and related settings, are stored locally by Gradey. They are not uploaded to Gradey's backend by the Planner feature. If you choose contextual AI, the selected Planner fields may be shared as described in section 3.5. Optional daily Planner reminders are scheduled locally on this device and respect notification permission, quiet hours and lock-screen privacy settings. They do not discover new school information while the app is closed.

If you enable Calendar export, Gradey requests permission to create and manage its events in Apple Calendar. It can access existing Calendar information needed to find, update or remove those events. Exported information may sync through the calendar account you use, such as iCloud or another provider, under that provider's settings and policy.

You can use the Planner without Calendar access. Personal Planner items are kept separately from school caches and are not automatically erased when you disconnect a school account.

## 4. Why we process data

We use personal data to provide the features you request, maintain your account, retrieve school information, deliver notifications, provide support, recognise purchases and protect the service.

Under the GDPR, the applicable legal basis depends on the processing:

- **Contract — Article 6(1)(b):** processing necessary to provide requested account, school, notification, support and purchase-related services.
- **Legitimate interests — Article 6(1)(f):** necessary and proportionate security, abuse prevention and operational diagnostics, taking account of your rights and interests.
- **Consent — Article 6(1)(a):** optional Gradey AI and other optional processing where consent is requested and required. You can withdraw consent without affecting the lawfulness of earlier processing.
- **Legal obligations — Article 6(1)(c):** processing required to comply with applicable law.

Device permissions control access to features such as Calendar, photos or the microphone. Granting a device permission does not make every use of the resulting information lawful. More information about these grounds is available from the [European Commission](https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/legal-grounds-processing-data_en).

## 5. Who receives data

Depending on the features you use, recipients include:

- **Open Side / Filip Bukovina:** operation of Gradey and its services.
- **Apple:** authentication, payments, notifications, device services and any Apple cloud services you use.
- **Supabase:** Gradey ID, linked accounts, encrypted session and push tokens, preferences and school data used for background marks, history and notifications.
- **Google Firebase:** AI authentication, backend processing, conversations, usage and consent records, and request security.
- **Microsoft Azure OpenAI:** messages and explicitly selected context needed to generate replies.
- **Intercom:** support sessions, messages, attachments and associated technical information.
- **RevenueCat:** purchase and entitlement processing.
- **Your school, canteen and calendar providers:** information necessary for connections and actions you request.

Providers may act as our processors or as independent controllers for their own services, depending on the activity. We may also disclose information where required by law or necessary to establish, exercise or defend legal claims.

## 6. International transfers

Some providers operate outside the European Economic Area or may access data from other countries. Where GDPR transfer safeguards are required, transfers must be covered by an applicable adequacy decision or appropriate safeguards, such as the European Commission's Standard Contractual Clauses.

Contact **filip@openside.tech** for information about the safeguards applicable to your data.

## 7. Retention and deletion

We retain account records, linked-account information and associated service data while needed to provide the service or meet an applicable legal requirement. Retention depends on the purpose of the record, whether your account or connection remains active, outstanding support or security matters, and any legal requirement to retain it.

You can disconnect linked accounts, request an export and delete your Gradey ID through the available account controls. Deleting Gradey ID removes its account and associated records from our active Gradey ID backend. It does not delete the account held by your school, canteen, Apple or another independent service.

AI conversations, support records and purchase records may be held in separate systems. Use their available deletion controls or contact us for a request covering those records. We may retain limited information where necessary for a legal obligation, a security matter or a legal claim.

**Historical Bakaláři passwords:** Earlier versions uploaded passwords to our backend. On **8 September 2026**, we removed the password fields from the active backend database and verified that none remained in its encrypted provider records. Database writes now remove password fields before storage.

Historical backups and service logs are separate from the active database. They may retain older copies according to the relevant system's retention schedule and any applicable legal obligation. The 8 September cleanup did not verify or erase every historical backup, log or export, so it must not be understood as confirmation that all historical copies were deleted on that date. Contact **filip@openside.tech** for information about a specific record, its retention or a deletion request.

On-device data and Calendar exports are separate from backend records. Signing out clears the relevant school session, but personal Planner data can remain. Deleting the app does not guarantee removal of every Keychain item, cloud record, Watch copy or exported Calendar event. Manage those records through the relevant app, device or service controls.

## 8. Children and school-account permissions

Gradey processes school information that may concern children. Only connect an account you are entitled to use, whether as the student, a parent, a guardian or another authorised person.

The app asks users to select an age group. Users under 16, including those under 13, are asked to confirm parent or guardian permission before continuing. This is a self-declaration stored on the device; the age check does not collect a full date of birth or verify a guardian's identity.

Where parental authorisation is legally required for a particular use or consent-based processing, that authorisation must be obtained. If you believe a child's data is being processed without the required permission, contact us so we can review access and any removal request.

## 9. Your rights

Subject to the applicable conditions and exceptions, GDPR rights include access, correction, erasure, restriction, objection and data portability. You can withdraw consent for processing based on consent and complain to a supervisory authority. Rights also apply to certain decisions made solely through automated processing. See the [European Commission's explanation of individual rights](https://commission.europa.eu/law/law-topic/data-protection/information-individuals_en).

Use the available in-app export and deletion controls or write to **filip@openside.tech**. We may request information needed to verify that you are authorised to make the request.

Official school records remain under the school's or school-system operator's control. Gradey cannot correct a school's official record on its own; contact the school about those corrections.

## 10. Security

Security measures include HTTPS connections, device Keychain storage, encryption of stored backend session tokens, backend access controls and App Check for protected requests.

Local school-session Keychain records are configured for the device that stores them rather than Keychain synchronisation between devices. Transfers to a paired Apple Watch are handled separately as described above.

No system can guarantee absolute security. Protect your Gradey ID, school account and device passcodes. School-access tokens still need protection even when a password is not uploaded to Gradey.

## 11. Changes to this policy

We may revise this policy when the app, data processing or applicable requirements change. The effective date will identify the current version, and material changes will be communicated through the app or Help Center where appropriate.

The policy is available in [English](https://help.bukovinafilip.com/en/articles/10-privacy-policy) and [Czech](https://help.bukovinafilip.com/cs/articles/10-privacy-policy).

## 12. Contact and complaints

Privacy requests: **filip@openside.tech**. Additional contact: **tom@openside.tech**.

You may complain to the Czech Office for Personal Data Protection, **Úřad pro ochranu osobních údajů (ÚOOÚ)**, Pplk. Sochora 27, 170 00 Praha 7, Czech Republic. Current contact details are on the [ÚOOÚ website](https://uoou.gov.cz/en/consultation/contact). You may also contact the competent supervisory authority in your country of residence, work or the place of an alleged infringement.
