// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OneTranslate",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OneTranslate", targets: ["OneTranslate"])
    ],
    targets: [
        .executableTarget(name: "OneTranslate"),
        .testTarget(name: "OneTranslateTests", dependencies: ["OneTranslate"])
    ],
    swiftLanguageModes: [.v5]
)
