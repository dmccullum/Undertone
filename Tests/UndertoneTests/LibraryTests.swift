import XCTest
@testable import Undertone

final class LibraryTests: XCTestCase {
    @MainActor func testCustomLibrariesSurviveReloadAndDoNotOverwritePalettes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        model.savePalette(name: "Existing palette")
        let libraryID = try XCTUnwrap(model.createColorLibrary(name: "Campaign Colors"))
        model.saveColor(name: "Custom Blue", hex: "#012169", libraryID: libraryID)
        model.saveColor(name: "Invalid", hex: "bad hex")
        let reloaded = StudioModel(directory: folder)
        let library = try XCTUnwrap(reloaded.colorLibraries.first { $0.name == "Campaign Colors" })
        XCTAssertEqual(library.colors.map(\.hex), ["012169"])
        XCTAssertEqual(library.colors.first?.name, "Custom Blue")
        XCTAssertTrue(reloaded.palettes.contains { $0.name == "Existing palette" })
        XCTAssertEqual(LibraryColor.coldwellBanker.count, 12)
        XCTAssertTrue(reloaded.colorLibraries.first?.isBuiltIn == true)
    }

    @MainActor func testLibraryClickCanAddTheSameColorMoreThanOnce() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let blue = LibraryColor.coldwellBanker[0]
        XCTAssertFalse(model.containsColor(hex: blue.hex))
        model.addLibraryColor(blue)
        XCTAssertTrue(model.containsColor(hex: blue.hex))
        XCTAssertEqual(model.recipe.stops.last?.hex, blue.hex)
        model.addLibraryColor(blue)
        XCTAssertEqual(model.recipe.stops.filter { $0.hex == blue.hex }.count, 2)
    }

    @MainActor func testColorsCanBeClearedInEveryMode() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)

        for mode in GradientMode.allCases {
            model.recipe.mode = mode
            model.removeAllColors()
            XCTAssertTrue(model.recipe.stops.isEmpty)
        }
    }

    @MainActor func testColorLibraryExportAndImportCreatesAnIndependentCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let id = try XCTUnwrap(model.createColorLibrary(name: "Coastal"))
        model.saveColor(name: "Ocean", hex: "2068FF", libraryID: id)
        let data = try model.encodedColorLibrary(id: id)
        let importedID = try model.importColorLibrary(data: data)
        XCTAssertNotEqual(id, importedID)
        let imported = try XCTUnwrap(model.colorLibraries.first { $0.id == importedID })
        XCTAssertEqual(imported.name, "Coastal")
        XCTAssertEqual(imported.colors.map(\.hex), ["2068FF"])
        XCTAssertFalse(imported.isBuiltIn)
    }

    @MainActor func testRemovingAPaletteColorPersistsIncludingBuiltInPalettes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let library = try XCTUnwrap(model.colorLibraries.first)
        let color = try XCTUnwrap(library.colors.first)

        model.removeLibraryColor(id: color.id, from: library.id)

        let reloaded = StudioModel(directory: folder)
        let restoredLibrary = try XCTUnwrap(reloaded.colorLibraries.first { $0.id == library.id })
        XCTAssertFalse(restoredLibrary.colors.contains { $0.id == color.id })
        XCTAssertTrue(restoredLibrary.isBuiltIn)
    }
}
