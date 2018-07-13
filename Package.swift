// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "Upstream",
    products: [
        .executable(name: "upstream", targets: ["Upstream"])
    ],
    dependencies: [
        .package(url:"https://github.com/PerfectlySoft/Perfect-Notifications.git", .upToNextMajor(from: "3.0.0"))
    ],
    targets: [
        .target(name: "Upstream", dependencies: ["PerfectNotifications"], path: "Sources.Server")
    ]
)
