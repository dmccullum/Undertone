import CoreGraphics
import Foundation
import XCTest
@testable import Undertone

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

    func testSeedDoesNotAffectGradientWhenGrainIsDisabled() throws {
        var firstRecipe = testRecipe(seed: 10)
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
        recipe.angleDegrees = 0
        let horizontal = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))
        recipe.angleDegrees = 90
        let vertical = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))

        XCTAssertNotEqual(horizontal, vertical)
    }

    func testMagicSingleRendersFromOneColorAndRespondsToVariation() throws {
        var recipe = testRecipe()
        recipe.mode = .magicSingle
        recipe.stops = [ColorStop(hex: "2068FF", x: 0.5, y: 0.5)]
        recipe.grain = 0
        recipe.colorArc = 0
        let restrained = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))
        recipe.colorArc = 1
        let expressive = try pixels(in: GradientRenderer.render(recipe, width: 64, height: 40))

        XCTAssertNotEqual(restrained, expressive)
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

    func testRequiresAtLeastTwoStops() {
        var recipe = testRecipe()
        recipe.stops = [recipe.stops[0]]

        XCTAssertThrowsError(try GradientRenderer.render(recipe, width: 8, height: 8)) { error in
            XCTAssertEqual(error as? GradientRenderer.RenderError, .insufficientColorStops)
        }
    }

    // Run explicitly in a release build with
    // UNDERTONE_RENDERER_BENCHMARK=1 swift test -c release --filter RendererTests/testOptionalLargeRenderBenchmark
    func testOptionalLargeRenderBenchmark() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["UNDERTONE_RENDERER_BENCHMARK"] == "1",
            "Set UNDERTONE_RENDERER_BENCHMARK=1 to render 4K and 8K fixtures."
        )

        for (label, width, height) in [("4K", 3_840, 2_160), ("8K", 7_680, 4_320)] {
            let start = Date()
            let image = try GradientRenderer.render(testRecipe(), width: width, height: height)
            let duration = Date().timeIntervalSince(start)

            XCTAssertEqual(image.width, width)
            XCTAssertEqual(image.height, height)
            print("Undertone renderer \(label): \(String(format: "%.3f", duration))s")
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
