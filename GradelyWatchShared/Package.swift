// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GradelyWatchShared",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "GradelyWatchShared",
            targets: ["GradelyWatchShared"]
        )
    ],
    targets: [
        .target(name: "GradelyWatchShared"),
        .testTarget(
            name: "GradelyWatchSharedTests",
            dependencies: ["GradelyWatchShared"]
        )
    ]
)
