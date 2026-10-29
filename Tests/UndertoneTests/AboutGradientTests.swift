import CoreGraphics
import XCTest
@testable import Undertone
@testable import UndertoneKit

@MainActor
final class AboutGradientTests: XCTestCase {
    func testPointsRestWithoutAPointer() {
        let rest = CGPoint(x: 0.2, y: 0.7)
        XCTAssertEqual(AboutGradient.displaced(rest, around: nil, spin: 1, aspect: 1.4), rest)
    }

    func testPointerDrawsNearbyPointsInAndTurnsThem() {
        let rest = CGPoint(x: 0.6, y: 0.5), pointer = CGPoint(x: 0.5, y: 0.5)
        let moved = AboutGradient.displaced(rest, around: pointer, spin: 0, aspect: 1)
        XCTAssertLessThan(hypot(moved.x - pointer.x, moved.y - pointer.y), 0.1)
        XCTAssertNotEqual(moved.y, rest.y, accuracy: 0.01)
    }

    func testFarPointsBarelyMove() {
        let rest = CGPoint(x: 0, y: 0), pointer = CGPoint(x: 1, y: 1.4)
        let moved = AboutGradient.displaced(rest, around: pointer, spin: 0, aspect: 1.4)
        XCTAssertEqual(moved.x, rest.x, accuracy: 0.01)
        XCTAssertEqual(moved.y, rest.y, accuracy: 0.01)
    }

    func testShuffleWalksTheStartersThenGeneratesPalettes() {
        let gradient = AboutGradient()
        XCTAssertEqual(gradient.name, "Dusk")
        gradient.shuffle()
        XCTAssertEqual(gradient.name, "Tidal")
        gradient.shuffle()
        XCTAssertEqual(gradient.name, "Ember")
        gradient.shuffle()
        XCTAssertEqual(gradient.hexes.count, 4)
        XCTAssertTrue(gradient.hexes.allSatisfy { Hex.normalized($0) == $0 })
        XCTAssertFalse(gradient.recipe.textureEnabled)
        XCTAssertEqual(gradient.recipe.mode, .organic)
    }

    func testTextColorFollowsThePalette() throws {
        let light = try GradientRenderer.render(AboutGradient.restRecipe(["F4F0E8", "FFFFFF"], randomized: false), width: 40, height: 56)
        let dark = try GradientRenderer.render(AboutGradient.restRecipe(["0A1730", "1B3C55"], randomized: false), width: 40, height: 56)
        XCTAssertGreaterThan(try XCTUnwrap(AboutGradient.textLuminance(light)), 0.8)
        XCTAssertLessThan(try XCTUnwrap(AboutGradient.textLuminance(dark)), 0.3)
    }

    func testGrainIsBuiltOnce() throws {
        let images = try XCTUnwrap(AboutGrain.images(width: 64, height: 48))
        XCTAssertEqual(images.light.width, 64)
        XCTAssertEqual(images.dark.height, 48)
        XCTAssertTrue(try XCTUnwrap(AboutGrain.images(width: 64, height: 48)).light === images.light)
    }
}
