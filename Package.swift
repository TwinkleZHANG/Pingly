// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Pingly",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pingly", targets: ["Pingly"])
    ],
    targets: [
        .executableTarget(
            name: "Pingly",
            path: "Sources/Pingly",
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "PinglyTests",
            dependencies: ["Pingly"],
            path: "Tests/PinglyTests"
        )
    ]
)
