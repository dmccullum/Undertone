import XCTest
@testable import Undertone

final class LibraryTests: XCTestCase {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @MainActor func testCustomLibrariesSurviveReload() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let libraryID = try XCTUnwrap(model.createColorLibrary(name: "Campaign Colors"))
        model.saveColor(name: "Custom Blue", hex: "#012169", libraryID: libraryID)
        model.saveColor(name: "Invalid", hex: "bad hex")
        let reloaded = StudioModel(directory: folder)
        let library = try XCTUnwrap(reloaded.colorLibraries.first { $0.name == "Campaign Colors" })
        XCTAssertEqual(library.colors.map(\.hex), ["012169"])
        XCTAssertEqual(library.colors.first?.name, "Custom Blue")
        XCTAssertEqual(LibraryColor.coldwellBanker.count, 12)
        XCTAssertEqual(reloaded.colorLibraries.first?.id, ColorLibrary.coldwellBankerID)
    }

    @MainActor func testLibraryClicksAddTheSameColorAgain() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let blue = LibraryColor.coldwellBanker[0]
        XCTAssertEqual(model.count(of: blue.hex), 0)
        model.addLibraryColor(blue)
        model.addLibraryColor(blue)
        XCTAssertEqual(model.count(of: blue.hex), 2)
        XCTAssertEqual(model.recipe.stops.last?.hex, blue.hex)
    }

    @MainActor func testEditsToASavedGradientGoIntoAnUnsavedCopy() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let original = try XCTUnwrap(model.currentGradient)

        model.recipe.softness = 0.2
        model.recipe.flow = 0.7
        model.saveNow()
        XCTAssertNotEqual(model.currentGradientID, original.id)
        XCTAssertEqual(model.gradients.filter(\.isUnsaved).count, 1, "One copy per editing run, not per change")
        XCTAssertTrue(model.isCurrentUnsaved)
        XCTAssertEqual(model.currentSource?.id, original.id)
        XCTAssertEqual(model.currentGradient?.recipe.softness, 0.2)
        XCTAssertEqual(model.gradients.first { $0.id == original.id }?.recipe, original.recipe, "The saved gradient is untouched")

        let reloaded = StudioModel(directory: folder)
        XCTAssertEqual(reloaded.currentGradientID, model.currentGradientID, "Unsaved work survives relaunch")
        XCTAssertEqual(reloaded.recipe.softness, 0.2)
    }

    @MainActor func testSaveAsNewKeepsTheSourceAndUpdateOverwritesIt() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        let dusk = try XCTUnwrap(model.currentGradient)

        step(undoManager) { model.recipe.softness = 0.2 }
        step(undoManager) { model.saveAsNewGradient() }
        let copy = try XCTUnwrap(model.currentGradient)
        XCTAssertFalse(copy.isUnsaved)
        XCTAssertEqual(copy.name, "Dusk 2")
        XCTAssertEqual(model.gradients.first { $0.id == dusk.id }?.recipe, dusk.recipe)

        model.selectGradient(id: dusk.id)
        step(undoManager) { model.recipe.softness = 0.4 }
        step(undoManager) { model.updateSavedGradient() }
        XCTAssertEqual(model.currentGradientID, dusk.id)
        XCTAssertEqual(model.currentGradient?.recipe.softness, 0.4)
        XCTAssertFalse(model.gradients.contains(where: \.isUnsaved))

        undoManager.undo()
        XCTAssertTrue(model.isCurrentUnsaved, "Undo brings the unsaved copy back")
        XCTAssertEqual(model.gradients.first { $0.id == dusk.id }?.recipe, dusk.recipe)
    }

    @MainActor func testSavedGradientsReorderAroundUnsavedOnes() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        step(undoManager) { model.recipe.softness = 0.2 }
        let unsavedID = try XCTUnwrap(model.currentGradientID)
        XCTAssertEqual(model.gradients.filter { !$0.isUnsaved }.map(\.name), ["Dusk", "Tidal", "Ember"])

        step(undoManager) { model.moveSavedGradients(fromOffsets: [2], toOffset: 0) }
        XCTAssertEqual(model.gradients.filter { !$0.isUnsaved }.map(\.name), ["Ember", "Dusk", "Tidal"])
        XCTAssertEqual(model.gradients.first?.id, unsavedID, "Unsaved gradients keep their places")
        XCTAssertEqual(StudioModel(directory: folder).gradients.filter { !$0.isUnsaved }.map(\.name), ["Ember", "Dusk", "Tidal"])

        undoManager.undo()
        XCTAssertEqual(model.gradients.filter { !$0.isUnsaved }.map(\.name), ["Dusk", "Tidal", "Ember"])
    }

    @MainActor func testLibraryColorsMoveWithinAndBetweenCollections() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        let brand = ColorLibrary.coldwellBankerID
        let blue = LibraryColor.coldwellBanker[0], gray = LibraryColor.coldwellBanker[1], mist = LibraryColor.coldwellBanker[2]
        var created: UUID?
        step(undoManager) { created = model.createColorLibrary(name: "Campaign") }
        let otherID = try XCTUnwrap(created)

        step(undoManager) { model.moveLibraryColors([blue.id], to: brand, before: mist.id) }
        XCTAssertEqual(model.colorLibraries.first { $0.id == brand }?.colors.prefix(3).map(\.id), [gray.id, blue.id, mist.id])

        step(undoManager) { model.moveLibraryColors([gray.id], to: otherID, before: nil) }
        XCTAssertEqual(model.colorLibraries.first { $0.id == otherID }?.colors.map(\.id), [gray.id])
        XCTAssertFalse(model.colorLibraries.first { $0.id == brand }?.colors.contains { $0.id == gray.id } ?? true)

        undoManager.undo()
        undoManager.undo()
        XCTAssertEqual(model.colorLibraries.first { $0.id == brand }?.colors, LibraryColor.coldwellBanker)
    }

    @MainActor func testRevertAndUntouchedCopiesLeaveNoUnsavedGradient() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let dusk = try XCTUnwrap(model.currentGradient)
        let tidal = try XCTUnwrap(model.gradients.first { $0.name == "Tidal" })

        model.recipe.softness = 0.2
        model.revertToSaved()
        XCTAssertEqual(model.currentGradientID, dusk.id)
        XCTAssertEqual(model.recipe, dusk.recipe)

        let original = model.recipe.softness
        model.recipe.softness = 0.3
        model.recipe.softness = original
        model.selectGradient(id: tidal.id)
        XCTAssertFalse(model.gradients.contains(where: \.isUnsaved), "A copy edited back to its source is dropped")
    }

    @MainActor func testReorderAndDuplicateColors() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let first = try XCTUnwrap(model.recipe.stops.first)
        model.moveColor(id: first.id, toIndex: 2)
        XCTAssertEqual(model.recipe.stops[2].id, first.id)
        model.duplicateColor(id: first.id)
        XCTAssertEqual(model.recipe.stops[3].hex, first.hex)
        XCTAssertEqual(model.recipe.stops.count, 5)
    }

    @MainActor func testColorsCanBeClearedInEveryMode() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)

        for mode in GradientMode.allCases {
            model.recipe.mode = mode
            model.removeAllColors()
            XCTAssertTrue(model.recipe.stops.isEmpty)
        }
    }

    @MainActor func testColorLibraryExportAndImportCreatesAnIndependentCopy() throws {
        let folder = temporaryFolder()
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
    }

    @MainActor func testFirstLaunchSeedsStarterGradients() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        XCTAssertEqual(model.gradients.map(\.name), ["Dusk", "Tidal", "Ember"])
        XCTAssertNotNil(model.currentGradientID)
        XCTAssertEqual(model.recipe, model.currentGradient?.recipe)
    }

    @MainActor func testGradientsSaveEverySettingAndReload() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let id = model.newGradient()
        XCTAssertTrue(model.recipe.stops.isEmpty)
        model.addColor(hex: "012169")
        model.recipe.mode = .radial
        model.recipe.centerX = 0.2
        model.recipe.stops[0].x = 0.11
        model.setCanvasSize(width: 2048, height: 2048)
        model.renameCurrentGradient("Harbor Test")
        model.saveNow()

        let reloaded = StudioModel(directory: folder)
        let saved = try XCTUnwrap(reloaded.gradients.first { $0.id == id })
        XCTAssertEqual(saved.name, "Harbor Test")
        XCTAssertTrue(saved.hasCustomName)
        XCTAssertEqual(saved.recipe, model.recipe)
        XCTAssertEqual(saved.recipe.width, 2048)
        XCTAssertEqual(saved.recipe.stops[0].x, 0.11)
    }

    @MainActor func testSelectingAGradientLoadsItsRecipe() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let tidal = try XCTUnwrap(model.gradients.first { $0.name == "Tidal" })
        model.selectGradient(id: tidal.id)
        XCTAssertEqual(model.recipe, tidal.recipe)
        XCTAssertEqual(model.currentName, "Tidal")
    }

    @MainActor func testDeletingTheLastGradientLeavesAFreshOne() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        for gradient in model.gradients { model.deleteGradient(id: gradient.id) }
        XCTAssertEqual(model.gradients.count, 1)
        XCTAssertEqual(model.currentGradientID, model.gradients.first?.id)
    }

    @MainActor func testLegacyPalettesBecomeGradients() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let palettes = [BrandPalette(name: "Open House", colors: ["012169", "B8CFEA", "F0F5FB"])]
        try JSONEncoder().encode(palettes).write(to: folder.appendingPathComponent("palettes.json"))

        let model = StudioModel(directory: folder)
        let migrated = try XCTUnwrap(model.gradients.first)
        XCTAssertEqual(model.gradients.count, 1)
        XCTAssertEqual(migrated.name, "Open House")
        XCTAssertTrue(migrated.hasCustomName)
        XCTAssertEqual(migrated.recipe.stops.map(\.hex), ["012169", "B8CFEA", "F0F5FB"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("palettes.json").path))
    }

    @MainActor func testAutomaticNamesFollowColorsUntilRenamed() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        model.newGradient()
        model.recipe.stops = [ColorStop(hex: "012169", x: 0.2, y: 0.2), ColorStop(hex: "B8CFEA", x: 0.8, y: 0.8)]
        let automatic = model.currentName
        XCTAssertEqual(automatic, NameGenerator.name(for: model.recipe, seed: try XCTUnwrap(model.currentGradient).nameSeed))

        model.renameCurrentGradient("Listing Hero")
        model.recipe.stops.append(ColorStop(hex: "F3AC91", x: 0.5, y: 0.5))
        XCTAssertEqual(model.currentName, "Listing Hero")
    }

    @MainActor func testCollectionFromGradientColorsUsesLibraryNames() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        model.recipe.stops = [ColorStop(hex: "012169", x: 0.2, y: 0.2), ColorStop(hex: "012169", x: 0.4, y: 0.4), ColorStop(hex: "F3AC91", x: 0.8, y: 0.8)]
        let id = try XCTUnwrap(model.createColorLibraryFromCurrentColors())
        let library = try XCTUnwrap(model.colorLibraries.first { $0.id == id })
        XCTAssertEqual(library.name, model.currentName)
        XCTAssertEqual(library.colors.map(\.name), ["Coldwell Banker Blue", ColorNamer.name("F3AC91")])
    }

    @MainActor func testUndoRestoresTheRecipe() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.undoManager = undoManager
        let original = model.recipe

        undoManager.beginUndoGrouping()
        model.recipe.flow = 0.9
        model.recipe.flow = 0.95
        undoManager.endUndoGrouping()
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(model.recipe, original)
        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        XCTAssertEqual(model.recipe.flow, 0.95)
    }

    @MainActor func testSliderResetsAreTheirOwnNamedUndoStep() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        let original = model.recipe.grain

        // A drag, then a reset well inside the drag's 700 ms burst: the reset is still its own step.
        step(undoManager) { model.recipe.grain = 0.4 }
        step(undoManager) { model.setRecipeValue(\.grain, to: original, undoName: "Reset Grain") }
        XCTAssertEqual(undoManager.undoActionName, "Reset Grain")

        undoManager.undo()
        XCTAssertEqual(model.recipe.grain, 0.4)
        undoManager.undo()
        XCTAssertEqual(model.recipe.grain, original)
    }

    /// A model wired to a manual-grouping undo manager, as in the window but one step per `step`.
    @MainActor private func undoableModel(in folder: URL) -> (StudioModel, UndoManager) {
        let model = StudioModel(directory: folder)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.undoManager = undoManager
        return (model, undoManager)
    }

    @MainActor private func step(_ undoManager: UndoManager, _ action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }

    @MainActor func testUndoRestoresColorEdits() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        let libraryID = ColorLibrary.coldwellBankerID
        func colors() -> [LibraryColor] { model.colorLibraries.first { $0.id == libraryID }?.colors ?? [] }
        let original = colors()

        step(undoManager) { model.saveColor(name: "Harbor", hex: "2A6F97", libraryID: libraryID) }
        XCTAssertEqual(undoManager.undoActionName, "Add Color")
        let added = try XCTUnwrap(colors().last)
        XCTAssertEqual(added.name, "Harbor")

        step(undoManager) { model.updateLibraryColor(added.id, in: libraryID, name: "Harbor", hex: "1F5673") }
        XCTAssertEqual(undoManager.undoActionName, "Edit Color")
        step(undoManager) { model.updateLibraryColor(added.id, in: libraryID, name: "Deep Harbor", hex: "1F5673") }
        XCTAssertEqual(undoManager.undoActionName, "Rename Color")
        step(undoManager) { model.deleteLibraryColor(original[0].id, from: libraryID) }
        XCTAssertEqual(undoManager.undoActionName, "Delete Color")
        XCTAssertFalse(colors().contains { $0.id == original[0].id })

        undoManager.undo()
        XCTAssertEqual(colors().first, original[0], "The deleted color returns to its place")
        undoManager.undo()
        XCTAssertEqual(colors().last?.name, "Harbor")
        undoManager.undo()
        XCTAssertEqual(colors().last?.hex, "2A6F97")
        undoManager.undo()
        XCTAssertEqual(colors(), original)

        undoManager.redo()
        XCTAssertEqual(colors().last?.name, "Harbor")
        XCTAssertEqual(undoManager.undoActionName, "Add Color")
        XCTAssertEqual(undoManager.redoActionName, "Edit Color")
    }

    @MainActor func testUndoRestoresCollections() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        let original = model.colorLibraries

        var createdID: UUID?
        step(undoManager) { createdID = model.createColorLibrary(name: "Coastal") }
        XCTAssertEqual(undoManager.undoActionName, "New Collection")
        let id = try XCTUnwrap(createdID)
        step(undoManager) { model.renameColorLibrary(id: id, to: "Shoreline") }
        XCTAssertEqual(undoManager.undoActionName, "Rename Collection")
        let data = try model.encodedColorLibrary(id: id)
        var importedID: UUID?
        step(undoManager) { importedID = try? model.importColorLibrary(data: data) }
        XCTAssertEqual(undoManager.undoActionName, "Import Collection")
        XCTAssertNotNil(importedID)
        step(undoManager) { model.deleteColorLibrary(id: ColorLibrary.coldwellBankerID) }
        XCTAssertEqual(undoManager.undoActionName, "Delete Collection")

        undoManager.undo()
        XCTAssertEqual(model.colorLibraries.first?.id, ColorLibrary.coldwellBankerID)
        XCTAssertEqual(StudioModel(directory: folder).colorLibraries.first?.id, ColorLibrary.coldwellBankerID, "Undo is saved")
        undoManager.undo()
        XCTAssertFalse(model.colorLibraries.contains { $0.id == importedID })
        undoManager.undo()
        XCTAssertEqual(model.colorLibraries.first { $0.id == id }?.name, "Coastal")
        undoManager.undo()
        XCTAssertEqual(model.colorLibraries, original)

        undoManager.redo()
        undoManager.redo()
        XCTAssertEqual(model.colorLibraries.first { $0.id == id }?.name, "Shoreline")
    }

    @MainActor func testUndoRestoresGradientName() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        step(undoManager) { model.newGradient() }
        let automatic = model.currentName

        step(undoManager) { model.renameCurrentGradient("Listing Hero") }
        XCTAssertEqual(undoManager.undoActionName, "Rename Gradient")
        let tidal = try XCTUnwrap(model.gradients.first { $0.name == "Tidal" })
        step(undoManager) { model.renameGradient(id: tidal.id, to: "Tidal Pool") }

        undoManager.undo()
        XCTAssertEqual(model.gradients.first { $0.id == tidal.id }?.name, "Tidal")
        undoManager.undo()
        XCTAssertEqual(model.currentName, automatic)
        XCTAssertEqual(model.currentGradient?.hasCustomName, false, "The name follows the colors again")
        undoManager.redo()
        XCTAssertEqual(model.currentName, "Listing Hero")
    }

    @MainActor func testGradientDeleteRedoesAndNewAndDuplicateUndo() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        let tidal = try XCTUnwrap(model.gradients.first { $0.name == "Tidal" })

        step(undoManager) { model.deleteGradient(id: tidal.id) }
        undoManager.undo()
        XCTAssertTrue(model.gradients.contains { $0.id == tidal.id })
        XCTAssertEqual(undoManager.redoActionName, "Delete Gradient")
        undoManager.redo()
        XCTAssertFalse(model.gradients.contains { $0.id == tidal.id }, "Redo deletes it again")
        undoManager.undo()
        XCTAssertTrue(model.gradients.contains { $0.id == tidal.id })

        let count = model.gradients.count
        let openID = model.currentGradientID
        var newID: UUID?
        step(undoManager) { newID = model.newGradient() }
        XCTAssertEqual(undoManager.undoActionName, "New Gradient")
        undoManager.undo()
        XCTAssertEqual(model.gradients.count, count)
        XCTAssertEqual(model.currentGradientID, openID)
        undoManager.redo()
        XCTAssertEqual(model.currentGradientID, newID)

        step(undoManager) { model.duplicateGradient(id: tidal.id) }
        XCTAssertEqual(undoManager.undoActionName, "Duplicate Gradient")
        undoManager.undo()
        XCTAssertFalse(model.gradients.contains { $0.name == "Tidal 2" })
    }

    @MainActor func testOpeningAnotherGradientKeepsLibraryUndo() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, undoManager) = undoableModel(in: folder)
        let blue = LibraryColor.coldwellBanker[0]

        step(undoManager) { model.deleteLibraryColor(blue.id, from: ColorLibrary.coldwellBankerID) }
        step(undoManager) { model.recipe.flow = 0.91 }
        let tidal = try XCTUnwrap(model.gradients.first { $0.name == "Tidal" })
        model.selectGradient(id: tidal.id)

        XCTAssertEqual(undoManager.undoActionName, "Delete Color", "Recipe steps are dropped, library steps stay")
        undoManager.undo()
        XCTAssertEqual(model.colorLibraries.first?.colors.first, blue)
        XCTAssertEqual(model.recipe, tidal.recipe)
    }

    @MainActor func testOldMeshRecipesOpenAsTheNearestGrid() throws {
        let json = """
        {"mode": "mesh", "version": 3, "stops": [
            {"id": "00000000-0000-0000-0000-000000000001", "hex": "012169", "x": 0.1, "y": 0.1},
            {"id": "00000000-0000-0000-0000-000000000002", "hex": "F0F5FB", "x": 0.9, "y": 0.9}
        ]}
        """
        let recipe = try StudioModel.validatedRecipe(from: Data(json.utf8))
        XCTAssertEqual(recipe.meshVertices.count, 9)
        XCTAssertEqual(recipe.meshVertices.first?.hex, "012169")
        XCTAssertEqual(recipe.meshVertices.last?.hex, "F0F5FB")
        XCTAssertEqual(recipe.version, GradientRecipe.currentVersion)

        let reencoded = try JSONDecoder().decode(GradientRecipe.self, from: JSONEncoder().encode(recipe))
        XCTAssertEqual(reencoded, recipe)
    }

    @MainActor func testMeshEditingKeepsTheBorderOnTheCanvas() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        model.setMode(.mesh)

        model.moveMeshVertex(0, x: 0.4, y: 0.3)
        XCTAssertEqual([model.meshVertices[0].x, model.meshVertices[0].y], [0, 0], "Corners stay put")
        model.moveMeshVertex(1, x: 0.7, y: 0.4)
        XCTAssertEqual(model.meshVertices[1].y, 0, "Top edge points slide along the edge")
        XCTAssertEqual(model.meshVertices[1].x, 0.7)
        model.moveMeshVertex(4, x: 0.62, y: 0.2)
        XCTAssertEqual(model.meshVertices[4].x, 0.62)

        let stop = try XCTUnwrap(model.recipe.stops.last)
        model.setMeshColor(stop.hex, at: 4)
        XCTAssertEqual(model.meshColor(at: 4), stop.hex)

        model.setMeshSize(4)
        XCTAssertEqual(model.meshVertices.count, 16)
        XCTAssertEqual([model.meshVertices[0].x, model.meshVertices[0].y], [0, 0])
        XCTAssertEqual(model.meshVertices[15].x, 1)
        model.moveMeshVertex(5, x: 0.95, y: 0.95)
        XCTAssertLessThan(model.meshVertices[5].x, model.meshVertices[6].x, "Points stay between their neighbors, so the grid can't fold")
        XCTAssertLessThan(model.meshVertices[5].y, model.meshVertices[9].y)

        model.straightenMesh()
        XCTAssertEqual(model.meshVertices.map(\.x), MeshGrid.regular(size: 4).map(\.x))
        for _ in 0..<20 {
            let random = StudioModel.randomized(model.recipe)
            let vertices = MeshGrid.vertices(for: random)
            XCTAssertTrue(vertices[0 ..< 4].allSatisfy { $0.y == 0 } && vertices[12 ..< 16].allSatisfy { $0.y == 1 })
        }
    }

    /// Any number of tray colors fills either grid evenly, with each color in one connected patch.
    @MainActor func testAutomaticMeshFillIsEvenAndConnected() {
        for size in MeshGrid.sizes {
            let points = size * size
            for count in 1...StudioModel.maximumStops {
                let colors = (0..<points).map { MeshGrid.automaticStopIndex(at: $0, size: size, count: count) }
                let shares = (0..<count).map { color in colors.filter { $0 == color }.count }
                XCTAssertEqual(Set(colors).count, count, "\(count) colors on \(size)×\(size)")
                XCTAssertLessThanOrEqual(shares.max()! - shares.min()!, 1)
                for color in 0..<count {
                    let members = (0..<points).filter { colors[$0] == color }
                    var reached: Set<Int> = [members[0]], frontier = [members[0]]
                    while let point = frontier.popLast() {
                        for other in members where !reached.contains(other)
                            && abs(other / size - point / size) <= 1 && abs(other % size - point % size) <= 1 {
                            reached.insert(other); frontier.append(other)
                        }
                    }
                    XCTAssertEqual(reached.count, members.count, "Color \(color) of \(count) on \(size)×\(size) is one patch")
                }
            }
        }
    }

    @MainActor func testShuffleMeshColorsKeepsEachColorsShare() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        model.setMode(.mesh)
        let before = model.meshVertices.map(\.hex)
        model.shuffleMeshColors()
        let after = model.meshVertices.map(\.hex)
        XCTAssertEqual(before.sorted(), after.sorted())
        XCTAssertNotEqual(before, after)
    }

    /// Mesh points own their colors: library clicks paint the selected point and step to the next, and
    /// the gradient's color list follows what's on the grid.
    @MainActor func testLibraryClicksPaintMeshPointsInOrder() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = StudioModel(directory: folder)
        let undoManager = UndoManager()
        model.undoManager = undoManager
        model.setMode(.mesh)
        let blue = LibraryColor.coldwellBanker[0], tide = LibraryColor.coldwellBanker[3]

        model.selectMeshPoint(3)
        model.addLibraryColor(blue)
        model.addLibraryColor(tide)
        XCTAssertEqual(model.meshColor(at: 3), blue.hex)
        XCTAssertEqual(model.meshColor(at: 4), tide.hex)
        XCTAssertEqual(model.selectedMeshPoint, 5)
        XCTAssertEqual(model.count(of: blue.hex), 1)
        XCTAssertTrue(model.recipe.stops.contains { $0.hex == blue.hex } && model.recipe.stops.contains { $0.hex == tide.hex })

        // Painting every point blue leaves blue as the only color in the list.
        for index in 0..<9 { model.setMeshColor(blue.hex, at: index) }
        XCTAssertEqual(model.recipe.stops.map(\.hex), [blue.hex])
        XCTAssertEqual(model.count(of: blue.hex), 9)

        model.selectMeshPoint(8)
        model.addLibraryColor(tide)
        XCTAssertEqual(model.selectedMeshPoint, 0, "Painting wraps back to the first point")
    }

    /// Version 4 files named a tray color per point, or none for the automatic fill.
    @MainActor func testVersionFourMeshPointsResolveToColors() throws {
        let json = """
        {"mode": "mesh", "version": 4, "meshSize": 3, "stops": [
            {"id": "00000000-0000-0000-0000-000000000001", "hex": "012169", "x": 0.1, "y": 0.1},
            {"id": "00000000-0000-0000-0000-000000000002", "hex": "F0F5FB", "x": 0.9, "y": 0.9}
        ], "meshVertices": [
            {"x": 0, "y": 0, "stopID": "00000000-0000-0000-0000-000000000002"}, {"x": 0.5, "y": 0}, {"x": 1, "y": 0},
            {"x": 0, "y": 0.5}, {"x": 0.5, "y": 0.5}, {"x": 1, "y": 0.5},
            {"x": 0, "y": 1}, {"x": 0.5, "y": 1}, {"x": 1, "y": 1}
        ]}
        """
        let recipe = try StudioModel.validatedRecipe(from: Data(json.utf8))
        XCTAssertEqual(recipe.meshVertices[0].hex, "F0F5FB", "A pinned point keeps its color")
        XCTAssertEqual(recipe.meshVertices[8].hex, "F0F5FB")
        XCTAssertEqual(recipe.meshVertices[1].hex, "012169", "Unpinned points take the automatic fill")
        XCTAssertEqual(recipe.version, GradientRecipe.currentVersion)
    }
}
