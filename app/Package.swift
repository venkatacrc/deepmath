// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeepMath",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DeepMath",
            resources: [.copy("Resources/deck.json"), .copy("Resources/web")]
        )
    ]
)
