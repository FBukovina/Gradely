# Hugeicons for Swift

A high-performance SwiftUI icon library with 5,100+ icons across 10 styles. Each style is a separate module, so you only bundle what you need.

> **⚠️ Pro License Required**: This package is available exclusively to Hugeicons Pro subscribers. [Get access](https://hugeicons.com/pricing)

## Features

- 🎨 **9 Icon Styles**: Solid (Sharp, Rounded, Standard), Stroke (Sharp, Rounded, Standard), Duotone, Twotone, Bulk
- 📦 **Modular**: Import only the styles you need to keep your app size minimal
- ⚡ **High Performance**: Fonts are loaded on-demand and cached
- 🎭 **Two-Layer Support**: Automatic rendering for Duotone, Twotone, and Bulk styles
- 🔤 **Ligature-Based**: Use icon names like "home-01" directly
- 🎯 **Type-Safe**: Built-in style detection and validation

## Installation

### Download Package

1. Log in to your Hugeicons account at [hugeicons.com](https://hugeicons.com)
2. Navigate to **Downloads** → **Swift Package**
3. Download `hugeicons-swift.zip`
4. Extract the zip file

### Add to Xcode Project

**Method 1: Local Package (Recommended)**

1. In Xcode, go to **File** → **Add Package Dependencies...**
2. Click **Add Local...**
3. Select the extracted `hugeicons-swift` folder
4. Choose the style modules you need:
   - `HugeiconsCore` (required)
   - `HugeiconsSolidRounded` (or any other style you want)
5. Click **Add Package**

**Method 2: Drag and Drop**

1. Drag the `hugeicons-swift` folder into your Xcode project navigator
2. Select "Copy items if needed"
3. Add to your target

**Method 3: Package.swift**

If you're building a Swift package, add as a local dependency:

```swift
dependencies: [
    .package(path: "../hugeicons-swift")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "HugeiconsCore", package: "hugeicons-swift"),
            .product(name: "HugeiconsSolidRounded", package: "hugeicons-swift"),
        ]
    )
]
```

## Quick Start

```swift
import SwiftUI
import HugeiconsCore
import HugeiconsSolidRounded

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Single-layer icon
            HugeiconsText(
                "home-01",
                font: HugeiconsSolidRounded.hugeiconsFont(size: 32)
            )
            .foregroundColor(.blue)
        }
    }
}
```

## Available Styles

### Single-Layer Styles
- `HugeiconsSolidSharp` - Solid icons with sharp corners
- `HugeiconsSolidRounded` - Solid icons with rounded corners
- `HugeiconsSolidStandard` - Solid icons with standard corners
- `HugeiconsStrokeSharp` - Stroke icons with sharp corners
- `HugeiconsStrokeRounded` - Stroke icons with rounded corners
- `HugeiconsStrokeStandard` - Stroke icons with standard corners

### Two-Layer Styles
- `HugeiconsDuotoneRounded` - Two-tone icons with rounded style
- `HugeiconsTwotoneRounded` - Two-tone icons with rounded style
- `HugeiconsBulkRounded` - Bulk style with rounded corners

## Usage Examples

### Basic Icon

```swift
import HugeiconsCore
import HugeiconsSolidSharp

HugeiconsText(
    "home-01",
    font: HugeiconsSolidSharp.hugeiconsFont(size: 24)
)
.foregroundColor(.red)
```

### Two-Layer Icon (Auto-Detection)

```swift
import HugeiconsCore
import HugeiconsDuotoneRounded

// Automatically renders both layers
HugeiconsText(
    "home-01",
    font: HugeiconsDuotoneRounded.hugeiconsFont(size: 32),
    color: .blue
)
// Primary: blue, Secondary: blue with 30% opacity
```

### Two-Layer Icon (Custom Colors)

```swift
HugeiconsText(
    "star-01",
    font: HugeiconsBulkRounded.hugeiconsFont(size: 48),
    primaryColor: .yellow,
    secondaryColor: .orange.opacity(0.3)
)
```

### Preload Fonts (Optional)

For zero-latency on first render, preload fonts at app startup:

```swift
@main
struct MyApp: App {
    init() {
        // Preload the styles you use
        _ = HugeiconsSolidRounded.load()
        _ = HugeiconsDuotoneRounded.load()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Using with Standard SwiftUI Modifiers

```swift
HugeiconsText("home-01", font: HugeiconsSolidRounded.hugeiconsFont(size: 24))
    .foregroundColor(.primary)
    .padding()
    .background(Color.blue.opacity(0.1))
    .cornerRadius(8)
```

## API Reference

### `HugeiconsText`

The main view for rendering icons.

```swift
// Simple usage with auto-detection
HugeiconsText(_ iconName: String, font: HugeiconsFont, color: Color = .primary)

// Custom layer colors (for two-layer styles)
HugeiconsText(_ iconName: String, font: HugeiconsFont, primaryColor: Color?, secondaryColor: Color?)
```

### Style Modules

Each style module provides:

```swift
// Get a HugeiconsFont (recommended for auto-detection)
StyleModule.hugeiconsFont(size: CGFloat) -> HugeiconsFont

// Get a SwiftUI Font (legacy, requires explicit style for two-layer icons)
StyleModule.font(size: CGFloat) -> Font

// Preload the font
StyleModule.load() -> String?

// Get the style enum
StyleModule.style -> HugeiconsStyle
```

## Performance

- **Lazy Loading**: Fonts are registered on first use
- **Caching**: PostScript names are cached after registration
- **Minimal Bundle Size**: Only include the styles you need
- **GPU Accelerated**: Uses native SwiftUI Text rendering

## Requirements

- iOS 14.0+ / macOS 11.0+ / tvOS 14.0+ / watchOS 7.0+
- Swift 5.5+
- Xcode 13.0+

## Finding Icons

Browse all 40,000+ icons at [hugeicons.com/icons](https://hugeicons.com/icons)

Icon names use the format: `icon-name-##` (e.g., `home-01`, `home-02`, `star-03`)

## License

See [LICENSE](LICENSE) for details.

## Updates

New versions of the package will be available in your Hugeicons account dashboard. Simply download the latest version and replace the old package in your project.

## Credits

Created and maintained by the Hugeicons team.

