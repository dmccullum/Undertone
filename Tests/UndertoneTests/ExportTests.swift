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
        recipe.mode = .linear
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

    func testMagicLinearFilesOpenAsLinearAndOldLinearStaysStraight() throws {
        let encoded = try JSONEncoder().encode(GradientRecipe())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "version")

        object["mode"] = "magicLinear"
        object["colorArc"] = 0.7
        let magic = try JSONDecoder().decode(GradientRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(magic.mode, .linear)
        XCTAssertEqual(magic.colorArc, 0.7)

        object["mode"] = "linear"
        let plain = try JSONDecoder().decode(GradientRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(plain.mode, .linear)
        XCTAssertEqual(plain.colorArc, 0)

        object["mode"] = "magicSingle"
        let tonal = try JSONDecoder().decode(GradientRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(tonal.mode, .tonal)
    }
}
