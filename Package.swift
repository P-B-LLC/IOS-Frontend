// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "RepbaseAPI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "RepbaseAPI", targets: ["RepbaseAPI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-openapi-generator.git",
            exact: "1.13.0"
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-runtime.git",
            exact: "1.12.0"
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-urlsession.git",
            exact: "1.3.1"
        ),
        .package(
            url: "https://github.com/apple/swift-http-types.git",
            exact: "1.6.0"
        )
    ],
    targets: [
        .target(
            name: "RepbaseAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types")
            ],
            path: "API",
            exclude: [
                "API.md",
                "INTEGRATION.md"
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)
