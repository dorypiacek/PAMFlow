// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "UI", targets: ["UI"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "UI",
            dependencies: [
                .product(name: "Core", package: "Core")
            ],
            path: ".",
            exclude: ["Package.swift"]
        )
    ]
)
