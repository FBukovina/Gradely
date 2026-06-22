# Gradely

Gradely is a SwiftUI app for checking school data from Bakaláři and EduPage. It gives students a cleaner, faster view of subjects, weighted averages, recent marks, absences, timetables, and what-if grade calculations.

Gradely will be available on the App Store. Source code lives at [FBukovina/Gradely](https://github.com/FBukovina/Gradely).

## Features

- Sign in with a Bakaláři URL or an EduPage school subdomain, including EduPage parent accounts and 2FA.
- Store sessions securely in Keychain and renew expired Bakaláři tokens or EduPage cookies.
- Cache marks locally so the dashboard can show recent data while refreshing.
- View overall average, total marks, best subject, and subjects that need attention.
- Open a subject detail page with individual marks, weights, dates, absence data, and point-based marks.
- Try a theoretical mark and weight to preview the new subject average.
- Run UI tests against a built-in mock Bakalari client, no real school account required.

## Requirements

- macOS with Xcode installed.
- The project is currently configured with an iOS 26.5 deployment target.
- A Bakaláři- or EduPage-compatible school account for live use.

## Getting Started

1. Clone the repository.
2. Open `Gradely.xcodeproj` in Xcode.
3. Select the `Gradely` scheme.
4. Choose an iPhone simulator or a connected device.
5. Build and run.

For command-line builds, first check available simulator destinations:

```sh
xcodebuild -project Gradely.xcodeproj -scheme Gradely -showdestinations
```

Then build or test with one of the listed destinations:

```sh
xcodebuild -project Gradely.xcodeproj -scheme Gradely -destination 'platform=iOS Simulator,name=iPhone 17' build
```

```sh
xcodebuild -project Gradely.xcodeproj -scheme Gradely -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## School URL Setup

Use the same school address where you normally sign in. For EduPage, enter either the school subdomain (for example `myschool`) or its `https://myschool.edupage.org` URL.

1. Open your school's Bakalari login page in a browser.
2. Copy the school's main address, not the full redirected page after sign-in.
3. Paste it into the **School URL** field in Gradely.
4. If the copied link ends with `/login` or `/next/login`, remove that part.

Example:

```text
https://demo.bakalari.cz
```

Gradely also accepts the address without `https://`, for example `demo.bakalari.cz`, and adds the secure HTTPS part automatically.

## Nastavení URL školy

Použijte stejnou webovou adresu Bakaláři, na které se běžně přihlašujete ke školnímu účtu.

1. Otevřete v prohlížeči přihlašovací stránku Bakaláři vaší školy.
2. Zkopírujte hlavní adresu školy, ne celé přesměrování po přihlášení.
3. Vložte ji v Gradely do pole **URL školy**.
4. Pokud zkopírovaný odkaz končí `/login` nebo `/next/login`, tuto část smažte.

Příklad:

```text
https://demo.bakalari.cz
```

Gradely přijme i adresu bez `https://`, například `demo.bakalari.cz`, a zabezpečenou část HTTPS doplní automaticky.

## Project Structure

```text
Gradely/
  Services/       Provider-neutral repository plus Bakaláři and EduPage clients
  Stores/         Keychain-backed session storage and local marks cache
  ViewModels/     Observable state for login, dashboard, and subject detail
  Views/          SwiftUI screens and reusable UI components
  Support/        App environment, date formatting, grade math, URL normalization
  Resources/      Localized strings
GradelyTests/     Unit tests for decoding, grade math, sessions, and caching
GradelyUITests/   End-to-end UI tests with mock API data
```

## Testing

The app supports mock launch arguments for UI tests:

- `-uiTestingMockAPI` uses local preview data instead of live network calls.
- `-uiTestingLoggedIn` starts with a saved mock session.
- `-uiTestingCachedMarks` starts with cached mock marks.

The existing UI tests exercise login, the subject dashboard, subject detail, and the theoretical average calculator.

## Privacy

Gradely stores login tokens in Keychain and keeps the school URL in user defaults. EduPage credentials, session cookie, and selected child are stored with device-only Keychain accessibility so the app and Watch can renew sessions. Cached marks are written to the app's Application Support directory. The app requires HTTPS school URLs.

Gradely is not an official Bakaláři or EduPage product. EduPage support is an original Swift implementation informed by observed web behavior and the unofficial GPL-3.0 [EdupageAPI/edupage-api](https://github.com/EdupageAPI/edupage-api) project; that package is not bundled or linked.
