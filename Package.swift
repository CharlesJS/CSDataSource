// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "CSDataSource",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13)
    ],
    products: [
        .library(
            name: "CSDataSource",
            targets: ["CSDataSource"]
        ),
        .library(
            name: "CSDataSource+Foundation",
            targets: ["CSDataSource_Foundation"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/CharlesJS/CSDataProtocol", from: "0.1.0"),
        .package(url: "https://github.com/CharlesJS/CSErrors", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "CSDataSource",
            dependencies: [
                .product(name: "CSDataProtocol", package: "CSDataProtocol"),
                "CSErrors"
            ]
        ),
        .target(
            name: "CSDataSource_Foundation",
            dependencies: [
                "CSDataSource",
                .product(name: "CSDataProtocol+Foundation", package: "CSDataProtocol")
            ]
        ),
        .testTarget(
            name: "CSDataSourceTests",
            dependencies: ["CSDataSource", "CSDataSource_Foundation"]
        ),
    ]
)
