// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CSDataSource",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "CSDataSource",
            targets: ["CSDataSource"]
        ),
    ],
    traits: [
        "Foundation"
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(
            url: "https://github.com/CharlesJS/CSErrors",
            from: "2.0.0",
            traits: [
                .trait(name: "Foundation", condition: .when(traits: ["Foundation"]))
            ]
        ),
        .package(
            url: "https://github.com/CharlesJS/CSFileInfo",
            from: "0.5.0",
            traits: [
                .trait(name: "Foundation", condition: .when(traits: ["Foundation"]))
            ]
        ),
        .package(
            url: "https://github.com/CharlesJS/CSFileManager",
            from: "0.3.2",
            traits: [
                .trait(name: "Foundation", condition: .when(traits: ["Foundation"]))
            ]
        ),
        .package(url: "https://github.com/CharlesJS/SyncPolyfill", from: "0.1.1")
    ],
    targets: [
        .target(
            name: "CSDataSource",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                "CSErrors",
                "CSFileManager",
                "SyncPolyfill",
            ]
        ),
        .testTarget(
            name: "CSDataSourceTests",
            dependencies: [
                "CSDataSource",
                "CSFileInfo",
            ]
        ),
    ]
)
