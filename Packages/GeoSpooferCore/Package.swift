// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GeoSpooferCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GeoSpooferCore", targets: ["GeoSpooferCore"])
    ],
    targets: [
        .target(name: "GeoSpooferCore"),
        .testTarget(
            name: "GeoSpooferCoreTests",
            dependencies: ["GeoSpooferCore"]
        )
    ]
)
