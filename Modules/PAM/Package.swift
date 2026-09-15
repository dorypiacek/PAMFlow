// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PAM",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PAM", targets: ["PAM"])
    ],
    dependencies: [
        .package(path: "../../Core"),
        .package(path: "../../UI")
    ],
    targets: [
        .target(
            name: "PAM",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "UI", package: "UI")
            ],
            path: ".",
            exclude: ["Package.swift"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
