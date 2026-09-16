import AppKit
import XCTest
@testable import Undertone

final class ExportTests: XCTestCase {
    @MainActor func testPNGAndJPEGEncodeAtRequestedDimensions() throws {
        let image = try GradientRenderer.render(GradientRecipe(), width: 320, height: 180)
        for jpeg in [false, true] {
            let data = try StudioModel.encoded(image, jpeg: jpeg)
            let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(decoded.pixelsWide, 320)
            XCTAssertEqual(decoded.pixelsHigh, 180)
            XCTAssertGreaterThan(data.count, 100)
        }
    }
    func testRecipeRoundTripPreservesComposition() throws {
        var recipe = GradientRecipe()
        recipe.mode = .magicLinear
        recipe.angleDegrees = 127
        recipe.colorArc = 0.82
        XCTAssertEqual(try JSONDecoder().decode(GradientRecipe.self, from: JSONEncoder().encode(recipe)), recipe)
    }

    func testOlderRecipeWithoutGradientModeUsesOrganicDefaults() throws {
        let encoded = try JSONEncoder().encode(GradientRecipe())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["mode", "angleDegrees", "gradientPosition", "fadeWidth", "easing", "colorArc", "centerX", "centerY"] {
            object.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(GradientRecipe.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertEqual(decoded.mode, .organic)
        XCTAssertEqual(decoded.fadeWidth, 1)
        XCTAssertEqual(decoded.centerX, 0.5)
    }
}
