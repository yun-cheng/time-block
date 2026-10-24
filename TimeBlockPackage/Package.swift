// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeBlock",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TimeBlockKit", targets: ["TimeBlockKit"]),
    ],
    targets: [
        .target(name: "TimeBlockKit"),
        .testTarget(name: "TimeBlockKitTests", dependencies: ["TimeBlockKit"]),
    ]
)
