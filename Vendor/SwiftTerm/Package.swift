// swift-tools-version:5.9

// Slim manifest for the Shade vendor copy of SwiftTerm. Upstream ships a much
// larger package (tests, benchmarks, a fuzzer, a sample TerminalApp, an
// asciinema-style player, multi-platform builds). Shade only consumes the
// SwiftTerm library on macOS, so we exclude everything else — keeps the
// resolve graph tight and avoids referencing Sources/ directories we trimmed
// when vendoring.

import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftTerm", targets: ["SwiftTerm"]),
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            dependencies: [],
            path: "Sources/SwiftTerm",
            exclude: ["Mac/README.md"],
            resources: [
                // Metal shaders bundled with the package (Bundle.module).
                .process("Apple/Metal/Shaders.metal"),
            ]
        ),
    ]
)
