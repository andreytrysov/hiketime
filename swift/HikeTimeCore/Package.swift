// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HikeTimeCore",
    products: [
        .library(name: "HikeTimeCore", targets: ["HikeTimeCore"])
    ],
    targets: [
        .target(name: "HikeTimeCore"),
        .executableTarget(
            name: "hiketime-verify",
            dependencies: ["HikeTimeCore"]
        ),
        .testTarget(
            name: "HikeTimeCoreTests",
            dependencies: ["HikeTimeCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
