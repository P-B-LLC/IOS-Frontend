// swift-tools-version: 6.1
import Foundation
import PackageDescription

// The runner copies the production sources into a temporary package so these
// tests exercise the real auth code without an iOS simulator or app signing.
let repository = ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"]!
let package = Package(
    name: "AccountSafety",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "RepbaseAPI", path: repository),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", exact: "1.12.0")
    ],
    targets: [
        .target(name: "AccountSafety", dependencies: [
            .product(name: "RepbaseAPI", package: "RepbaseAPI"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
        ]),
        .testTarget(name: "AccountSafetyTests", dependencies: [
            "AccountSafety",
            // Direct, so the transport tests can reach the middlewares with
            // @testable. They live in the API client rather than in the app.
            .product(name: "RepbaseAPI", package: "RepbaseAPI"),
            // Also direct: the cancellation tests build the `ClientError` the
            // generated client would have thrown, so they need the type
            // rather than only the code that inspects it.
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
        ])
    ]
)
