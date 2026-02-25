// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Whisprr",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Whisprr",
            path: "Sources/Whisprr"
        )
    ]
)
