# Gradey for Windows

Native Windows 10/11 desktop client for **Gradey (Gradely)** built with **.NET 10** and **WPF**, with zero external NuGet dependencies.

## Features

- **School Providers**: Full support for **Bakaláři API v3** (including automatic school directory search, rotating refresh token renewal, and silent re-authentication) and **EduPage** (including 2FA code & mobile approval polling, and parent child-profile switching).
- **Design Parity**: Embedded **Space Grotesk** typography, Light/Dark/System themes with Windows 11 **Mica** & dark titlebar DWM integration, and Gradey's ambient teal/emerald **Aurora** backdrop.
- **Today Dashboard**: Live 60-second lesson countdowns, horizontal lesson strip, current & next lesson progress, timetable changes, recent marks, upcoming planner/homework items, and today's canteen lunch.
- **Marks & What-If Calculator**: Persistent desktop master-detail split view, Priority/Average sorting, 3-tier weight resolution (including backtracking inference from official averages), interactive **Average History Chart** (reversed Y-axis, weight-scaled dots, hover scrubbing), and live local + Bakaláři remote What-If grade simulation.
- **Timetable**: Weekly 5-day grid with week navigation (`Ctrl+Left` / `Ctrl+Right`), Actual vs. Permanent toggle, color-coded changes (Canceled, Substitution, Room Changed, Added), lesson detail inspector, and one-click Add to Planner.
- **Absence Analytics**: Total hours breakdown, per-subject risk bars, misses-until-limit & Czech semester allowance outlook, What-If absence predictor, monthly stacked bar chart, and **local-only hide/restore day overrides** (with automatic review pause if school records change).
- **Komens, Planner & Report Cards**: Mail-style split-pane Komens reader (Received + Noticeboard + attachment downloads), unified School Homework + Personal Planner window, and current-semester Report Card estimator with borderline warnings + historical report cards.
- **Strava.cz Canteen**: Balance overview, daily meal menus, allergens, and meal ordering/cancellation with replacement confirmation.
- **Privacy & Security**: Credentials and session tokens are encrypted per-user locally using native **Windows DPAPI** (`crypt32.dll`), and all school communication uses HTTPS.
- **Localization**: Live **Čeština** and **English** switching (plus optional *Chronically Online* dialect toggle) in Settings (`Ctrl+,`).

## Requirements

- Windows 10 or Windows 11 (x64 / ARM64)
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) (or later)

## Build & Run

```powershell
# Build solution
dotnet build GradelyWindows/GradelyWindows.sln

# Run the native Windows app
dotnet run --project GradelyWindows/Gradely.Windows/Gradely.Windows.csproj

# Launch directly into Demo Mode (no school account required)
dotnet run --project GradelyWindows/Gradely.Windows/Gradely.Windows.csproj -- --demo
```

## Run Automated Tests

```powershell
dotnet run --project GradelyWindows/Gradely.Core.Tests/Gradely.Core.Tests.csproj
```

## Publish Standalone Windows Executable

```powershell
dotnet publish GradelyWindows/Gradely.Windows/Gradely.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## Keyboard Shortcuts

- `Ctrl + 1` – `5`: Switch between Today, Marks, Absence, Timetable, and Meals
- `Ctrl + R`: Refresh school data
- `Ctrl + N`: Create a new Planner item
- `Ctrl + Left` / `Right`: Previous / Next week in Timetable
- `Ctrl + ,`: Open Settings
- `Esc`: Close open modal windows
