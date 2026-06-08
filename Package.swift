// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ProgressApp",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "ProgressApp", targets: ["ProgressApp"]),
        .executable(name: "duaswift", targets: ["duaswift"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
    ],
    targets: [
        .executableTarget(
            name: "ProgressApp",
            path: "Sources/ProgressApp"
        ),
        .executableTarget(
            name: "duaswift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/duaswift",
            // TEMPORARY: staged to Swift 5 mode so the existing code keeps
            // building during the refactor. Removed in the final task to turn
            // on Swift 6 strict data-race checking.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "duaswiftTests",
            dependencies: ["duaswift"],
            path: "Tests/duaswiftTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
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
