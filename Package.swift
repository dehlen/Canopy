// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "Debris",
    products: [
        .executable(name: "debris", targets: ["Debris"]),
        .library(name: "Roots", targets: ["Roots"])
    ],
    dependencies: [
        .package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer.git", from: "3.0.0"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", from: "3.0.0"),
        .package(url: "https://github.com/mxcl/PromiseKit.git", from: "6.3.4"),
        .package(url: "https://github.com/PromiseKit/Foundation.git", from: "3.0.0"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-CURL.git", from: "3.0.0"),
        .package(url: "https://github.com/mxcl/LegibleError.git", from: "1.0.0"),
        .package(url: "https://github.com/toto/CCurl.git", from: "0.4.0"),
        .package(url: "https://github.com/PerfectlySoft/Perfect-Crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "Debris", dependencies: ["PerfectSQLite", "PerfectHTTPServer", "PerfectCURL", "Roots", "APNs"], path: "Sources/Linux"),
        .target(name: "Roots", dependencies: ["PromiseKit", "PMKFoundation", "LegibleError"], path: "Sources/Model/xp", exclude: ["Client"]),
        .target(name: "APNs", dependencies: ["PerfectCrypto"])
    ]
)

package.platforms = [.macOS(.v10_12)]
