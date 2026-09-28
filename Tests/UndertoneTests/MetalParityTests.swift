import CoreGraphics
import Foundation
import Metal
import XCTest
@testable import Undertone

/// The quality gate for the GPU renderer: every style, grain included, must match the CPU reference
/// within 2/255 on every channel of every pixel.
final class MetalParityTests: XCTestCase {
    private static let tolerance = 2

    func testEveryStyleMatchesTheCPUReference() throws {
        let gpu = try renderer()
        var report: [String] = []
        for (name, recipe) in Self.cases() {
            for (width, height) in Self.sizes {
                let cpu = try pixels(GradientRenderer.render(recipe, width: width, height: height))
                let metal = try pixels(gpu.render(recipe, width: width, height: height))
                let stats = Self.compare(cpu, metal)
                report.append("\(name) \(width)×\(height): max \(stats.max), off by 1: \(stats.offByOne), off by 2+: \(stats.offByMore)")
                XCTAssertLessThanOrEqual(stats.max, Self.tolerance, "\(name) at \(width)×\(height)")
            }
        }
        print("Metal parity\n" + report.joined(separator: "\n"))
    }

    /// The per-Mac gate the app runs at launch: this Mac's GPU must match the CPU within 2/255 on the
    /// fixtures, and the engine then renders on the GPU.
    func testThisMacPassesTheLaunchSelfTest() throws {
        let gpu = try renderer()
        let worst = try RenderEngine.selfTest(gpu)
        print("Launch self-test: largest channel difference \(worst)/255")
        XCTAssertLessThanOrEqual(worst, RenderEngine.tolerance)
        XCTAssertTrue(RenderEngine.usesGPU)
    }

    /// Full export sizes. Slow on the CPU in debug builds, so run on demand:
    ///     UNDERTONE_PARITY_FULL=1 swift test -c release --filter MetalParityTests
    func testFullSizeExportsMatch() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UNDERTONE_PARITY_FULL"] == "1", "Set UNDERTONE_PARITY_FULL=1 for full-size parity.")
        let gpu = try renderer()
        for (name, recipe) in Self.cases() {
            for (width, height) in [(2_160, 2_880), (3_840, 2_160)] {
                let cpuStart = Date()
                let cpu = try pixels(GradientRenderer.render(recipe, width: width, height: height))
                let cpuTime = Date().timeIntervalSince(cpuStart)
                let gpuStart = Date()
                let metal = try pixels(gpu.render(recipe, width: width, height: height))
                let gpuTime = Date().timeIntervalSince(gpuStart)
                let stats = Self.compare(cpu, metal)
                print(String(format: "%@ %d×%d: max %d, off by 1 %.4f%%, off by 2 %.4f%% · CPU %.3fs, GPU %.3fs", name, width, height, stats.max,
                             Double(stats.offByOne) / Double(cpu.count) * 100, Double(stats.offByMore) / Double(cpu.count) * 100, cpuTime, gpuTime))
                XCTAssertLessThanOrEqual(stats.max, Self.tolerance, "\(name) at \(width)×\(height)")
            }
        }
    }

    /// Preview speed at full Retina resolution, straight into a texture as the canvas would draw it:
    ///     UNDERTONE_RENDERER_BENCHMARK=1 swift test -c release --filter MetalParityTests/testOptionalPreviewBenchmark
    func testOptionalPreviewBenchmark() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UNDERTONE_RENDERER_BENCHMARK"] == "1", "Set UNDERTONE_RENDERER_BENCHMARK=1.")
        let gpu = try renderer()
        let (width, height) = (1_840, 2_454)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .private
        let texture = try XCTUnwrap(gpu.device.makeTexture(descriptor: descriptor))
        for (name, recipe) in Self.cases().prefix(GradientMode.allCases.count) {
            var times: [Double] = []
            for _ in 0..<12 {
                let start = Date()
                let scene = try GradientRenderer.Scene(recipe, width: width, height: height)
                let commands = try XCTUnwrap(gpu.makeCommandBuffer())
                try gpu.encodePreview(scene, into: texture, on: commands)
                commands.commit()
                commands.waitUntilCompleted()
                times.append(Date().timeIntervalSince(start))
            }
            let median = times.sorted()[times.count / 2]
            print(String(format: "Preview %@ %d×%d: %.1f ms per frame (median of 12, scene setup included)", name, width, height, median * 1000))
        }
    }

    // MARK: - Fixtures

    /// Debug builds render the CPU reference slowly, so they check one small, odd size.
    #if DEBUG
    static let sizes = [(193, 257)]
    #else
    static let sizes = [(257, 343), (640, 480)]
    #endif

    static func cases() -> [(String, GradientRecipe)] {
        let four = [
            ColorStop(hex: "E78670", x: 0.12, y: 0.18), ColorStop(hex: "6445A8", x: 0.82, y: 0.24),
            ColorStop(hex: "F2C66D", x: 0.31, y: 0.86), ColorStop(hex: "012169", x: 0.7, y: 0.7),
        ]
        let base = GradientRecipe(stops: four, grain: 0.2, grainSize: 1, seed: 8_675_309)
        var cases: [(String, GradientRecipe)] = []
        func add(_ name: String, _ change: (inout GradientRecipe) -> Void) {
            var recipe = base
            change(&recipe)
            cases.append((name, recipe))
        }
        for mode in GradientMode.allCases {
            add(mode.title) { $0.mode = mode }
        }
        add("Organic crisp swirl") { $0.softness = 0.05; $0.flow = 1; $0.swirl = 0.8; $0.grainSize = 2.4 }
        add("Organic soft, eight colors") {
            $0.softness = 1; $0.grain = 0.5
            $0.stops += ["FF006E", "3A86FF", "FFBE0B", "8338EC"].enumerated().map { ColorStop(hex: $1, x: 0.2 * Double($0 + 1), y: 0.5) }
        }
        add("Mesh 4×4 bent crisp") {
            $0.mode = .mesh; $0.meshSize = 4; $0.softness = 0
            $0.meshVertices = [(0, 0), (0.42, 0), (0.72, 0), (1, 0), (0, 0.28), (0.22, 0.4), (0.6, 0.2), (1, 0.38),
                               (0, 0.7), (0.45, 0.78), (0.8, 0.52), (1, 0.66), (0, 1), (0.25, 1), (0.62, 1), (1, 1)].map { MeshVertex(x: $0.0, y: $0.1) }
        }
        add("Mesh dreamy, coarse grain") { $0.mode = .mesh; $0.softness = 1; $0.grainSize = 3 }
        add("Tonal swirl") { $0.mode = .tonal; $0.swirl = 0.7; $0.colorArc = 1 }
        add("Linear crisp arc") { $0.mode = .linear; $0.smoothBlend = false; $0.colorArc = 0.8; $0.startX = 0.1; $0.endY = 0.9 }
        add("Glow off canvas") { $0.mode = .radial; $0.centerX = -0.4; $0.centerY = 1.3; $0.fadeWidth = 1.4 }
        add("Aurora angled") { $0.mode = .aurora; $0.angleDegrees = 70; $0.flow = 1 }
        add("No colors") { $0.stops = [] }
        add("One color") { $0.stops = [ColorStop(hex: "2068FF", x: 0.5, y: 0.5)] }
        add("No grain") { $0.textureEnabled = false }
        return cases
    }

    static func compare(_ lhs: [UInt8], _ rhs: [UInt8]) -> (max: Int, offByOne: Int, offByMore: Int) {
        var maximum = 0, offByOne = 0, offByMore = 0
        for index in lhs.indices {
            let difference = abs(Int(lhs[index]) - Int(rhs[index]))
            maximum = max(maximum, difference)
            if difference == 1 { offByOne += 1 } else if difference > 1 { offByMore += 1 }
        }
        return (maximum, offByOne, offByMore)
    }

    private func renderer() throws -> MetalRenderer {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("This Mac has no Metal device.") }
        return try MetalRenderer()
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        guard let data = image.dataProvider?.data else { throw CocoaError(.fileReadCorruptFile) }
        return [UInt8](data as Data)
    }
}
