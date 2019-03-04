// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "Debris",
    products: [
        .executable(name: "debris", targets: ["Debris"]),
        .library(name: "Roots", targets: ["Roots"])
    ],
    dependencies: [
        .package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.3.4")),
        .package(url: "https://github.com/PromiseKit/Foundation.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/PerfectlySoft/Perfect-CURL.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/mxcl/LegibleError.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "Debris", dependencies: ["PerfectSQLite", "PerfectHTTPServer", "PerfectCURL", "Roots"], path: "Sources/Linux"),
        .target(name: "Roots", dependencies: ["PromiseKit", "PMKFoundation", "LegibleError"], path: "Sources/Model/xp", exclude: ["Client"])
    ]
)
