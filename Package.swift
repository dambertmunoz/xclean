// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "xclean",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "xclean", targets: ["xclean"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "xclean",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/xclean"
        ),
        .testTarget(
            name: "xcleanTests",
            dependencies: ["xclean"],
            path: "Tests/xcleanTests"
        )
    ]
)
