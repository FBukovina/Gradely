# Gradely

Gradely is a SwiftUI iOS app for checking school marks from the Bakalari API. It gives students a cleaner, faster view of subjects, weighted averages, recent marks, absences, and what-if grade calculations.

Gradely will be available on the App Store. Source code lives at [FBukovina/Gradely](https://github.com/FBukovina/Gradely).

## Features

- Sign in with a school Bakalari URL, username, and password.
- Store sessions securely in Keychain and refresh expired access tokens.
- Cache marks locally so the dashboard can show recent data while refreshing.
- View overall average, total marks, best subject, and subjects that need attention.
- Open a subject detail page with individual marks, weights, dates, absence data, and point-based marks.
- Try a theoretical mark and weight to preview the new subject average.
- Run UI tests against a built-in mock Bakalari client, no real school account required.

## Requirements

- macOS with Xcode installed.
- The project is currently configured with an iOS 26.5 deployment target.
- A Bakalari-compatible school URL and account for live use.

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

## Project Structure

```text
Gradely/
  Services/       Bakalari API client and repository layer
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

Gradely stores login tokens in the iOS Keychain and keeps the school URL in user defaults. Cached marks are written to the app's Application Support directory. The app requires HTTPS school URLs.

Gradely is not an official Bakalari product.
