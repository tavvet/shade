// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shade",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Four Shade feature patches plus a Swift 6.2 compatibility fix. Candidate
        // branch: shade/update-1.99.3. Pin the immutable revision; see
        // docs/swiftterm-1.99.3-update.md for validation and manual checks.
        .package(url: "https://github.com/tavvet/SwiftTerm", revision: "67d31e95f7e06fc228da38a36d1d1f6035296abf"),
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
