// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "GitBell.Server",
    products: [
        .executable(name: "gitbell", targets: ["gitbell"])
    ],
    dependencies: [
        .package(url: "https://github.com/IBM-Swift/BlueSocket.git", from: "1.0.10")
    ],
    targets: [
        .target(name: "gitbell", dependencies: ["Socket"], path: "Sources.Server")
    ]
)
