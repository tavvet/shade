// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shade",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Fork of migueldeicaza/SwiftTerm carrying Shade's patches, rebased on
        // upstream. Pinned by revision for reproducibility; sync = rebase the
        // `shade` branch on upstream/main and bump this SHA. See
        // docs/swiftterm-fork-migration.md.
        .package(url: "https://github.com/tavvet/SwiftTerm", revision: "87eb734e9a2e866f8a5c50945a58837a935b08e4"),
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
