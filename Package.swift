// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FIND950",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "S950Library", targets: ["S950Library"]),
        .executable(name: "find950-cli", targets: ["FIND950CLI"]),
        .executable(name: "FIND950", targets: ["FIND950"])
    ],
    targets: [
        .target(name: "S950Library"),
        .executableTarget(name: "FIND950CLI", dependencies: ["S950Library"]),
        .executableTarget(
            name: "FIND950",
            dependencies: ["S950Library"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreText")
            ]
        ),
        .testTarget(name: "S950LibraryTests", dependencies: ["S950Library"])
    ]
)
