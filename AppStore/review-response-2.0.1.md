# App Review response — Gradey 2.0.1 (build 1)

Submission addressed: `bb7bc802-d62e-44bf-ba74-e7cc44ad33fc`

> Draft only. Do not paste or submit until the physical-device sandbox purchase and recording have succeeded and the four rejected subscriptions are attached to the new app version.

## Notes for App Review

We resolved the Guideline 2.1(b) issue in a new binary, version 2.0.1 build 1.

All four auto-renewable Support subscriptions are implemented with StoreKit and are visible in the app:

- Support Monthly — `com.bukovinafilip.BakalariMarks.support.standard.monthly`
- Support Yearly — `com.bukovinafilip.BakalariMarks.support.standard.yearly`
- Extra Support Monthly — `com.bukovinafilip.BakalariMarks.support.plus.monthly`
- Extra Support Yearly — `com.bukovinafilip.BakalariMarks.support.plus.yearly`

The new binary also loads these products directly from StoreKit if the RevenueCat offering is unavailable or incomplete, and it keeps every subscription row independently discoverable by accessibility and UI automation.

Reviewer path:

1. Launch Gradey and sign in using the demo account in App Review Information.
2. On the Today screen, tap the Settings button in the top-right corner.
3. Open **Subscriptions, help & feedback**.
4. Tap **Support subscriptions & tips**.
5. The **Monthly** segment displays Support Monthly and Extra Support Monthly.
6. Select **Yearly** to display Support Yearly and Extra Support Yearly.
7. Tap a subscription to open Apple's purchase sheet.
8. **Restore purchases** is available below the products.

We have attached a physical-device recording showing the core app flow and a successful sandbox subscription purchase.

## Physical-device recording checklist

- Start on the device Home Screen.
- Launch Gradey.
- Sign in with the App Review demo account.
- Briefly demonstrate the Today screen and another core feature such as Marks.
- Open Settings → Subscriptions, help & feedback → Support subscriptions & tips.
- Show both Monthly products.
- Switch to Yearly and show both Yearly products.
- Complete one subscription purchase with a Sandbox Apple Account and show the successful result.
- Show Restore purchases.
- If one-time tips remain submitted as IAPs, demonstrate that purchase flow too.

## Reply to the reviewer

Hello,

Thank you for the review. We resolved the Guideline 2.1(b) issue in Gradey 2.0.1 build 1. The new binary includes StoreKit purchase flows for Support Monthly, Support Yearly, Extra Support Monthly, and Extra Support Yearly. We also added direct StoreKit fallback loading so the four products remain visible if the RevenueCat offering is unavailable or incomplete.

The subscriptions can be found at Today → Settings → Subscriptions, help & feedback → Support subscriptions & tips. Monthly and Yearly products are displayed in their corresponding segments, with Restore purchases below them.

We resubmitted the rejected subscription products with the new binary and attached a physical-device recording in App Review Information showing the core app flow and a successful sandbox purchase.

Thank you.
