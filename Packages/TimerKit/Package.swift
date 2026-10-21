// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimerKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TimerKit", targets: ["TimerKit"])
    ],
    targets: [
        .target(name: "TimerKit"),
        .testTarget(name: "TimerKitTests", dependencies: ["TimerKit"])
    ]
)
