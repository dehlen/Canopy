// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "Debris",
    products: [
        .executable(name: "debris", targets: ["debris"]),
        .library(name: "Roots", targets: ["Roots"])
    ],
    dependencies: [
        .package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/PerfectlySoft/Perfect-Notifications.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.3.4"))
    ],
    targets: [
        .target(name: "debris", dependencies: ["PerfectNotifications", "PerfectSQLite", "Roots"], path: "Sources.Server"),
        .target(name: "Roots", dependencies: ["PromiseKit"], path: "Sources.Common", exclude: ["Client.etc.swift", "Vendor/Keychain.swift", "Vendor/SKProductsRequest+Promise.swift", "SubscriptionsManager.swift"])
    ]
)
