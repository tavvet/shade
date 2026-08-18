// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shade",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Fork of migueldeicaza/SwiftTerm carrying Shade's patches, rebased on
        // upstream. Pinned by revision for reproducibility; sync = rebase the
        // fork `main` on upstream/main and bump this SHA. See
        // docs/swiftterm-fork-migration.md.
        .package(url: "https://github.com/tavvet/SwiftTerm", revision: "c665309f8fb31ad3600c93aa3a957b573e964dd2"),
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
