// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hugeicons",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .tvOS(.v14),
        .watchOS(.v7)
    ],
    products: [
        .library(name: "HugeiconsCore", targets: ["HugeiconsCore"]),
        .library(name: "HugeiconsStrokeRounded", targets: ["HugeiconsStrokeRounded"])
    ],
    targets: [
        .target(
            name: "HugeiconsCore",
            path: "Sources/HugeiconsCore"
        ),
        .target(
            name: "HugeiconsStrokeRounded",
            dependencies: ["HugeiconsCore"],
            path: "Sources/HugeiconsStrokeRounded",
            resources: [.process("Fonts")]
        )
    ]
)
