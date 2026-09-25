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

    @MainActor func testLastCompositionIsRestoredOnLaunch() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        model.recipe.mode = .aurora
        model.recipe.colorArc = 0.61
        model.recipe.stops = [.init(hex: "123456", x: 0.2, y: 0.8)]
        model.refreshPreview()
        model.flushLastRecipe()

        let restored = StudioModel(directory: folder)
        XCTAssertEqual(restored.recipe.mode, .aurora)
        XCTAssertEqual(restored.recipe.colorArc, 0.61)
        XCTAssertEqual(restored.recipe.stops.map(\.hex), ["123456"])
    }

    @MainActor func testAuroraResetUsesZeroColorArc() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        model.recipe.mode = .aurora
        model.recipe.colorArc = 0.8
        model.resetGradientSettings()
        XCTAssertEqual(model.recipe.colorArc, 0)
    }
}
