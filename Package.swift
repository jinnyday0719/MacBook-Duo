// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacBookDuo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacBookDuoStage1", targets: ["MacBookDuoStage1"]),
        .executable(name: "MacBookDuo", targets: ["MacBookDuo"])
    ],
    targets: [
        .executableTarget(
            name: "MacBookDuo",
            path: "Sources/MacBookDuo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MacBookDuoStage1",
            path: "Sources/MacBookDuoStage1",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
