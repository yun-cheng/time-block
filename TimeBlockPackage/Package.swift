// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeBlock",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "TimeBlockKit", targets: ["TimeBlockKit"]),
        .library(name: "TimeBlockUI", targets: ["TimeBlockUI"]),
    ],
    targets: [
        .target(name: "TimeBlockKit"),
        .target(name: "TimeBlockUI", dependencies: ["TimeBlockKit"]),
        .executableTarget(name: "TimeBlockPrototype", dependencies: ["TimeBlockKit", "TimeBlockUI"]),
        .testTarget(name: "TimeBlockKitTests", dependencies: ["TimeBlockKit"]),
    ]
)
