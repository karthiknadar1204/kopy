// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Kopy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Kopy", targets: ["KopyApp"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "KopyCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "KopyApp",
            dependencies: ["KopyCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])]
        ),
        .testTarget(name: "KopyCoreTests", dependencies: ["KopyCore"]),
        .testTarget(name: "KopyAppTests", dependencies: ["KopyApp", "KopyCore"])
    ]
)
