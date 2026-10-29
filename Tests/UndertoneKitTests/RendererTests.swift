import CoreGraphics
import Foundation
import XCTest
@testable import UndertoneKit

final class RendererTests: XCTestCase {
    func testRenderHasRequestedDimensionsAndSRGBLayout() throws {
        let image = try GradientRenderer.render(testRecipe(), width: 37, height: 23)

        XCTAssertEqual(image.width, 37)
        XCTAssertEqual(image.height, 23)
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(image.bitsPerPixel, 32)
        XCTAssertEqual(image.bytesPerRow, 37 * 4)
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testRenderingIsDeterministic() throws {
        let recipe = testRecipe(seed: 8_675_309)

        let first = try pixels(in: GradientRenderer.render(recipe, width: 48, height: 32))
        let second = try pixels(in: GradientRenderer.render(recipe, width: 48, height: 32))

        XCTAssertEqual(first, second)
    }

    func testChangingSeedChangesSeededGrain() throws {
        let first = try pixels(in: GradientRenderer.render(testRecipe(seed: 10), width: 48, height: 32))
        let second = try pixels(in: GradientRenderer.render(testRecipe(seed: 11), width: 48, height: 32))

        XCTAssertNotEqual(first, second)
    }

    /// Organic, Mesh and Tonal use the seed to shape their flow field, so check a style that doesn't.
    func testSeedDoesNotAffectGradientWhenGrainIsDisabled() throws {
        var firstRecipe = testRecipe(seed: 10)
        firstRecipe.mode = .radial
        firstRecipe.grain = 0
        var secondRecipe = firstRecipe
        secondRecipe.seed = 11

        let first = try pixels(in: GradientRenderer.render(firstRecipe, width: 48, height: 32))
        let second = try pixels(in: GradientRenderer.render(secondRecipe, width: 48, height: 32))

        XCTAssertEqual(first, second)
    }

    func testEveryGradientModeRendersDistinctOutput() throws {
        var outputs: [Data] = []
        for mode in GradientMode.allCases {
            var recipe = testRecipe()
            recipe.mode = mode
            recipe.grain = 0
            outputs.append(try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40)))
        }

        XCTAssertEqual(Set(outputs).count, GradientMode.allCases.count)
    }

    func testLinearAngleChangesOutput() throws {
        var recipe = testRecipe()
        recipe.mode = .linear
        recipe.grain = 0
        recipe.startX = 0; recipe.startY = 0.5; recipe.endX = 1; recipe.endY = 0.5
        let horizontal = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))
        recipe.startX = 0.5; recipe.startY = 0; recipe.endX = 0.5; recipe.endY = 1
        let vertical = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))

        XCTAssertNotEqual(horizontal, vertical)
    }

    func testMagicSingleRendersFromOneColorAndRespondsToVariation() throws {
        var recipe = testRecipe()
        recipe.mode = .tonal
        recipe.stops = [ColorStop(hex: "2068FF", x: 0.5, y: 0.5)]
        recipe.grain = 0
        recipe.colorArc = 0
        let restrained = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))
        recipe.colorArc = 1
        let expressive = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))

        XCTAssertNotEqual(restrained, expressive)
    }

    func testMagicSingleSeedChangesCompositionWithoutGrain() throws {
        var recipe = testRecipe(seed: 10)
        recipe.mode = .tonal
        recipe.stops = [ColorStop(hex: "2068FF", x: 0.5, y: 0.5)]
        recipe.grain = 0
        let first = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))
        recipe.seed = 11
        let second = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))

        XCTAssertNotEqual(first, second)
    }

    func testRadialCenterChangesOutput() throws {
        var recipe = testRecipe()
        recipe.mode = .radial
        recipe.grain = 0
        recipe.centerX = 0.2
        let left = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))
        recipe.centerX = 0.8
        let right = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))

        XCTAssertNotEqual(left, right)
    }

    func testRadialCenterCanMoveOffCanvas() throws {
        var recipe = testRecipe()
        recipe.mode = .radial
        recipe.grain = 0
        recipe.centerX = 0.5
        let onCanvas = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))
        recipe.centerX = -0.5
        recipe.centerY = 1.4
        let offCanvas = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))

        XCTAssertNotEqual(onCanvas, offCanvas)
    }

    func testRejectsInvalidDimensionsAndExcessiveAllocation() {
        let recipe = testRecipe()

        XCTAssertThrowsError(try GradientRenderer.render(recipe, width: 0, height: 100)) { error in
            XCTAssertEqual(error as? GradientRenderer.RenderError, .invalidDimensions(width: 0, height: 100))
        }
        XCTAssertThrowsError(try GradientRenderer.render(recipe, width: 8_193, height: 1)) { error in
            XCTAssertEqual(error as? GradientRenderer.RenderError, .invalidDimensions(width: 8_193, height: 1))
        }
        XCTAssertThrowsError(try GradientRenderer.render(recipe, width: 8_192, height: 8_192)) { error in
            XCTAssertEqual(error as? GradientRenderer.RenderError, .imageTooLarge(width: 8_192, height: 8_192))
        }
    }

    func testRendersEmptyAndSingleColorCompositions() throws {
        var recipe = testRecipe()
        recipe.stops = []
        recipe.grain = 0
        let empty = try GradientRenderer.render(recipe, width: 8, height: 8)
        XCTAssertEqual(empty.width, 8)
        XCTAssertEqual(empty.height, 8)

        recipe.stops = [ColorStop(hex: "2068FF", x: 0.5, y: 0.5)]
        let single = try GradientRenderer.render(recipe, width: 8, height: 8)
        XCTAssertNotEqual(try pixels(in: empty), try pixels(in: single))
    }

    /// A mesh surface runs through its points, so each point's pixel shows exactly its tray color.
    func testMeshPassesThroughItsPoints() throws {
        var recipe = testRecipe()
        recipe.mode = .mesh
        recipe.grain = 0
        let image = try GradientRenderer.render(recipe, width: 41, height: 41)
        let data = try pixels(in: image)
        // Three colors fill nine points in diagonal runs: top left, the middle diagonal, bottom right.
        assertPixel(data, width: 41, x: 0, y: 0, matches: "E78670")
        assertPixel(data, width: 41, x: 40, y: 0, matches: "6445A8")
        assertPixel(data, width: 41, x: 20, y: 20, matches: "6445A8")
        assertPixel(data, width: 41, x: 40, y: 40, matches: "F2C66D")
    }

    func testMeshPointsOwnTheirColors() throws {
        var recipe = testRecipe()
        recipe.mode = .mesh
        recipe.grain = 0
        var vertices = MeshGrid.seeded(size: 3, colors: recipe.stops.map(\.hex))
        vertices[0].hex = "2068FF"
        recipe.meshVertices = vertices
        let data = try pixels(in: GradientRenderer.render(recipe, width: 41, height: 41))
        assertPixel(data, width: 41, x: 0, y: 0, matches: "2068FF")

        // A painted mesh renders even with no colors in the gradient's list.
        recipe.stops = []
        let alone = try pixels(in: GradientRenderer.render(recipe, width: 41, height: 41))
        assertPixel(alone, width: 41, x: 0, y: 0, matches: "2068FF")
    }

    /// The top of Mesh's Softness range blurs past the points for a hazier blend.
    func testFullMeshSoftnessIsSofterThanTheClassicBlend() throws {
        var recipe = testRecipe()
        recipe.mode = .mesh
        recipe.grain = 0
        func contrast(_ softness: Double) throws -> Double {
            recipe.softness = softness
            let data = try pixels(in: GradientRenderer.render(recipe, width: 41, height: 41))
            let values = stride(from: 0, to: data.count, by: 4).map { Double(data[$0]) + Double(data[$0 + 1]) + Double(data[$0 + 2]) }
            let mean = values.reduce(0, +) / Double(values.count)
            return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        }
        XCTAssertLessThan(try contrast(1), try contrast(0.5) * 0.85)
    }

    func testMovingAMeshPointBendsTheBlend() throws {
        var recipe = testRecipe()
        recipe.mode = .mesh
        recipe.grain = 0
        let even = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 64))
        var vertices = MeshGrid.seeded(size: 3, colors: recipe.stops.map(\.hex))
        vertices[4].x = 0.8
        vertices[4].y = 0.3
        recipe.meshVertices = vertices
        let bent = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 64))
        XCTAssertNotEqual(even, bent)
        // The center color now sits where the point moved.
        assertPixel(bent, width: 64, x: Int((0.8 * 63).rounded()), y: Int((0.3 * 63).rounded()), matches: "6445A8", tolerance: 4)
    }

    func testFourByFourMeshRenders() throws {
        var recipe = testRecipe()
        recipe.mode = .mesh
        recipe.grain = 0
        let three = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 64))
        recipe.meshSize = 4
        let four = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 64))
        XCTAssertNotEqual(three, four)
    }

    /// Organic mixes in OKLab: halfway between red and green is a bright yellow, not RGB's dark olive.
    func testOrganicBlendsInOKLab() throws {
        var recipe = testRecipe()
        recipe.stops = [ColorStop(hex: "FF0000", x: 0.25, y: 0.5), ColorStop(hex: "00FF00", x: 0.75, y: 0.5)]
        recipe.grain = 0
        recipe.flow = 0
        recipe.swirl = 0
        let data = try pixels(in: GradientRenderer.render(recipe, width: 41, height: 41))
        let offset = (20 * 41 + 20) * 4
        func linear(_ byte: UInt8) -> Double { let v = Double(byte) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(data[offset]) + 0.7152 * linear(data[offset + 1]) + 0.0722 * linear(data[offset + 2])
        XCTAssertGreaterThan(luminance, 0.8 * (0.2126 + 0.7152) / 2, "An RGB average would be about 0.2")
    }

    /// Still ignores Flow; Pull and Wave each move the colors their own way.
    func testOrganicFlowStyles() throws {
        var recipe = testRecipe()
        recipe.grain = 0
        func render(_ flow: OrganicFlow, strength: Double) throws -> Data {
            recipe.organicFlow = flow
            recipe.flow = strength
            return try pixels(in: GradientRenderer.render(recipe, width: 48, height: 64))
        }
        XCTAssertEqual(try render(.still, strength: 0.2), try render(.still, strength: 1))
        let still = try render(.still, strength: 1), pull = try render(.pull, strength: 1), wave = try render(.wave, strength: 1)
        XCTAssertNotEqual(still, pull)
        XCTAssertNotEqual(still, wave)
        XCTAssertNotEqual(pull, wave)
        XCTAssertEqual(try render(.pull, strength: 0), still, "No pull is Still")
        XCTAssertEqual(GradientRecipe().organicFlow, .still)
        let old = try JSONDecoder().decode(GradientRecipe.self, from: Data(#"{"mode": "organic"}"#.utf8))
        XCTAssertEqual(old.organicFlow, .still, "Older files open as Still")
    }

    func testOrganicAndMeshLookClearlyDifferent() throws {
        var recipe = testRecipe()
        recipe.grain = 0
        recipe.width = 60; recipe.height = 80
        let organic = try pixels(in: GradientRenderer.render(recipe, width: 60, height: 80))
        recipe.mode = .mesh
        let mesh = try pixels(in: GradientRenderer.render(recipe, width: 60, height: 80))
        let difference = zip(organic, mesh).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(organic.count) * 4 / 3
        XCTAssertGreaterThan(difference, 20, "Average per-channel difference out of 255")
    }

    /// A long, dark ramp with no grain (Coldwell Banker Blue into Midnight) must not step into bands.
    func testDarkRampsWithoutGrainDoNotBand() throws {
        var recipe = testRecipe()
        recipe.mode = .linear
        recipe.textureEnabled = false
        recipe.stops = [ColorStop(hex: "012169", x: 0, y: 0), ColorStop(hex: "0A1730", x: 1, y: 1)]
        recipe.startX = 0.5; recipe.startY = 0; recipe.endX = 0.5; recipe.endY = 1
        let height = 1_440
        let data = try pixels(in: GradientRenderer.render(recipe, width: 4, height: height))
        var longest = 1, run = 1
        for row in 1..<height {
            let current = (row * 4 + 1) * 4, previous = ((row - 1) * 4 + 1) * 4
            run = data[current..<current + 3] == data[previous..<previous + 3] ? run + 1 : 1
            longest = max(longest, run)
        }
        XCTAssertLessThan(longest, 16, "Without dither this ramp holds each level for about 40 pixels")
    }

    // Run explicitly in a release build with
    // UNDERTONE_RENDERER_BENCHMARK=1 swift test -c release --filter RendererTests/testOptionalLargeRenderBenchmark
    func testOptionalLargeRenderBenchmark() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["UNDERTONE_RENDERER_BENCHMARK"] == "1",
            "Set UNDERTONE_RENDERER_BENCHMARK=1 to render 4K and 8K fixtures."
        )

        for mode in GradientMode.allCases {
            for (label, width, height) in [("preview", 960, 1_280), ("thumbnail", 120, 90), ("4K", 3_840, 2_160), ("8K", 7_680, 4_320)] {
                var recipe = testRecipe()
                recipe.mode = mode
                let start = Date()
                let image = try GradientRenderer.render(recipe, width: width, height: height)
                let duration = Date().timeIntervalSince(start)

                XCTAssertEqual(image.width, width)
                XCTAssertEqual(image.height, height)
                print("Undertone renderer \(mode.title) \(label): \(String(format: "%.3f", duration))s")
            }
        }
    }

    private func testRecipe(seed: UInt64 = 42) -> GradientRecipe {
        GradientRecipe(
            stops: [
                ColorStop(hex: "E78670", x: 0.12, y: 0.18),
                ColorStop(hex: "6445A8", x: 0.82, y: 0.24),
                ColorStop(hex: "F2C66D", x: 0.31, y: 0.86),
            ],
            flow: 0.62,
            softness: 0.48,
            grain: 0.2,
            grainSize: 2,
            seed: seed,
            width: 48,
            height: 32
        )
    }

    private func assertPixel(_ data: Data, width: Int, x: Int, y: Int, matches hex: String, tolerance: Int = 2, file: StaticString = #filePath, line: UInt = #line) {
        let offset = (y * width + x) * 4
        let expected = Hex.components(hex)
        for (channel, value) in [expected.red, expected.green, expected.blue].enumerated() {
            XCTAssertLessThanOrEqual(abs(Int(data[offset + channel]) - Int((value * 255).rounded())), tolerance, "Channel \(channel) at \(x),\(y)", file: file, line: line)
        }
    }

    private func pixels(in image: CGImage) throws -> Data {
        guard let data = image.dataProvider?.data else {
            throw PixelError.missingData
        }
        return data as Data
    }

    private enum PixelError: Error {
        case missingData
    }
}
