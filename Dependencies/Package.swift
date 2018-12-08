// swift-tools-version:4.2

import PackageDescription

let pkg = Package(name: "Dependencies")
pkg.dependencies.append(.package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "3.1.0")))
pkg.dependencies.append(.package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.7.0")))
pkg.dependencies.append(.package(url: "https://github.com/PromiseKit/Foundation.git", .upToNextMajor(from: "3.3.0")))
pkg.dependencies.append(.package(url: "https://github.com/PromiseKit/StoreKit.git", .upToNextMajor(from: "3.1.0")))
pkg.dependencies.append(.package(url: "https://github.com/ole/SortedArray.git", .upToNextMajor(from: "0.7.0")))
