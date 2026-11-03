// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HarnessKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HarnessKit", targets: ["HarnessKit"]),
    ],
    targets: [
        .target(name: "HarnessKit"),
        .testTarget(name: "HarnessKitTests", dependencies: ["HarnessKit"]),
    ]
)
