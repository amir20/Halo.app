// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "ProgressApp", targets: ["ProgressApp"]),
        .executable(name: "duaswift", targets: ["duaswift"]),
        .executable(name: "Halo", targets: ["Halo"]),
        .library(name: "DiskKit", targets: ["DiskKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
    ],
    targets: [
        .executableTarget(
            name: "ProgressApp",
            path: "Sources/ProgressApp"
        ),
        // Disk-scanning model shared by the GUI (and reusable by the CLI):
        // a classified directory tree built from a real filesystem walk.
        .target(
            name: "DiskKit",
            path: "Sources/DiskKit"
        ),
        // "Halo" — a SwiftUI donut disk visualizer built on DiskKit.
        .executableTarget(
            name: "Halo",
            dependencies: ["DiskKit"],
            path: "Sources/Halo"
        ),
        .testTarget(
            name: "DiskKitTests",
            dependencies: ["DiskKit"],
            path: "Tests/DiskKitTests"
        ),
        .testTarget(
            name: "HaloTests",
            dependencies: ["Halo", "DiskKit"],
            path: "Tests/HaloTests"
        ),
        .executableTarget(
            name: "duaswift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/duaswift"
        ),
        .testTarget(
            name: "duaswiftTests",
            dependencies: ["duaswift"],
            path: "Tests/duaswiftTests"
        ),
        .plugin(
            name: "BundleApp",
            capability: .command(
                intent: .custom(
                    verb: "bundle-app",
                    description: "Build a release binary and package it into a double-clickable .app bundle"
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Write the generated ProgressApp.app bundle into the project directory"
                    )
                ]
            )
        )
    ]
)
