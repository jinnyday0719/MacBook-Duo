// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacBookDuo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacBookDuo", targets: ["MacBookDuo"])
    ],
    targets: [
        .executableTarget(
            name: "MacBookDuo",
            path: "Sources/MacBookDuo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
