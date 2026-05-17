// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shade",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0"),
    ],
    targets: [
        .executableTarget(
            name: "Shade",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/Shade"
        )
    ]
)
