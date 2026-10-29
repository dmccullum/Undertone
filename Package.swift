// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Undertone",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Undertone", targets: ["Undertone"]),
        // The renderer, for other apps: recipes in, CGImages out. Foundation, CoreGraphics and Metal only.
        .library(name: "UndertoneKit", targets: ["UndertoneKit"])
    ],
    dependencies: [
        // The family's shared package, checked out next to this repository.
        .package(path: "../DMKit")
    ],
    targets: [
        .target(name: "UndertoneKit"),
        .executableTarget(
            name: "Undertone",
            dependencies: ["UndertoneKit", .product(name: "DMKit", package: "DMKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "UndertoneKitTests", dependencies: ["UndertoneKit"]),
        .testTarget(name: "UndertoneTests", dependencies: ["Undertone", "UndertoneKit"])
    ],
    swiftLanguageModes: [.v6]
)
