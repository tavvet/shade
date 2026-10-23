// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shade",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Fork of migueldeicaza/SwiftTerm carrying four approved patches on
        // upstream v1.99.1. Pinned by published revision for reproducibility;
        // preserved by shade-pin-2026-10-23-r2. See
        // docs/swiftterm-fork-migration.md.
        .package(url: "https://github.com/tavvet/SwiftTerm", revision: "850f6469329bada193981efa8a7e6ccd3920792e"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "Shade",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/Shade"
        ),
        .testTarget(
            name: "ShadeTests",
            dependencies: ["Shade"],
            path: "Tests/ShadeTests"
        ),
    ]
)
