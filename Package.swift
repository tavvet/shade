// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shade",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Shade feature patches, trusted link cwd and Swift 6.2 compatibility. Candidate
        // branch: shade/update-1.99.3. Pin the immutable revision; see
        // docs/swiftterm-1.99.3-update.md for validation and manual checks.
        .package(url: "https://github.com/tavvet/SwiftTerm", revision: "b70b3b69c75c9bad189c27ffe073a8148cf9a6e2"),
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
