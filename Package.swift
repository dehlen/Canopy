// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "GitBell.Server",
    products: [
        .executable(name: "gitbell", targets: ["gitbell"])
    ],
    dependencies: [
        .package(url:"https://github.com/PerfectlySoft/Perfect-Notifications.git", .upToNextMajor(from: "3.0.0"))
    ],
    targets: [
        .target(name: "gitbell", dependencies: ["PerfectNotifications"], path: "Sources.Server")
    ]
)
