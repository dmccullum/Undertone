import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Undertone

/// Renders every `.undertone.json`/`.json` recipe in a folder to PNG, for visual before/after checks.
///
///     UNDERTONE_RENDER_IN=recipes UNDERTONE_RENDER_OUT=out swift test -c release --filter SampleRenderTests
final class SampleRenderTests: XCTestCase {
    func testRenderRecipeFolder() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["UNDERTONE_RENDER_IN"], let output = environment["UNDERTONE_RENDER_OUT"] else {
            throw XCTSkip("Set UNDERTONE_RENDER_IN and UNDERTONE_RENDER_OUT to render a folder of recipes.")
        }
        let longSide = Double(environment["UNDERTONE_RENDER_SIZE"] ?? "") ?? 640
        let inputURL = URL(fileURLWithPath: input), outputURL = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let recipe = try JSONDecoder().decode(GradientRecipe.self, from: Data(contentsOf: file))
            let scale = longSide / Double(max(recipe.width, recipe.height))
            let image = try GradientRenderer.render(recipe, width: Int(Double(recipe.width) * scale), height: Int(Double(recipe.height) * scale))
            let name = file.deletingPathExtension().lastPathComponent
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(outputURL.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
    }
}
