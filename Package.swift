// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitaScoreCore",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "GitaScoreCore", targets: ["GitaScoreCore"])],
    targets: [
        .target(name: "GitaScoreCore", path: "foxgita/Features/FollowScore/Core"),
        .testTarget(name: "GitaScoreCoreTests", dependencies: ["GitaScoreCore"], path: "foxgitaTests/FollowScoreCoreTests"),
    ]
)
