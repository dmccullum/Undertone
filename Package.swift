// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Undertone", platforms: [.macOS(.v14)], products: [.executable(name: "Undertone", targets: ["Undertone"])], targets: [.executableTarget(name: "Undertone"), .testTarget(name: "UndertoneTests", dependencies: ["Undertone"])], swiftLanguageModes: [.v5])
