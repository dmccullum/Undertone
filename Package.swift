// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Undertone",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Undertone", targets: ["Undertone"])],
    dependencies: [
        // The family's shared package, checked out next to this repository.
        .package(path: "../DMKit")
    ],
    targets: [
        .executableTarget(
            name: "Undertone",
            dependencies: [.product(name: "DMKit", package: "DMKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "UndertoneTests", dependencies: ["Undertone"])
    ],
    swiftLanguageModes: [.v6]
)
