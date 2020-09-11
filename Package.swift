// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let name = "Provider"
let package = Package(
    name: name,
    platforms: [.iOS(.v13)],
    products: [.library(name: name, targets: [name])],
    dependencies: [
        .package(
            url: "https://github.com/Lickability/Networking",
            from: "main"
        ),
        .package(
            url: "https://github.com/Lickability/Persister",
            from: "main"
        )
    ],
    targets: [.target(name: name)]
)
