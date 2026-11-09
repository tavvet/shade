// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shade",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Four focused Shade patches on upstream v1.99.3. Published candidate
        // branch: shade/update-1.99.3. Pin the immutable revision; see
        // docs/swiftterm-1.99.3-update.md for validation and manual checks.
        .package(url: "https://github.com/tavvet/SwiftTerm", revision: "e4c48d78035485cf5cc2d2986243156ac3e47703"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
    ],
    targets: [
        // UI-free logic: models, parsers, process/SSH command construction and
        // settings documents. It has no SwiftTerm or KeyboardShortcuts
        // dependency; ShadeCoreBoundaryTests keeps out AppKit, SwiftUI and
        // other UI frameworks.
        .target(
            name: "ShadeCore",
            path: "Sources/ShadeCore"
        ),
        .executableTarget(
            name: "Shade",
            dependencies: [
                "ShadeCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/Shade"
        ),
        .testTarget(
            name: "ShadeTests",
            dependencies: ["Shade", "ShadeCore"],
            path: "Tests/ShadeTests"
        ),
    ]
)
