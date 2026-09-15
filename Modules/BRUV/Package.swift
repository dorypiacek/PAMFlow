// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BRUV",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "BRUV", targets: ["BRUV"])
    ],
    dependencies: [
        .package(path: "../../Core"),
        .package(path: "../../UI"),
        .package(url: "https://github.com/dorypiacek/SharkTrackKit.git", branch: "main")
    ],
    targets: [
        .target(
            name: "BRUV",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "UI", package: "UI"),
                .product(name: "SharkTrackKit", package: "SharkTrackKit")
            ],
            path: ".",
            exclude: ["Package.swift"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
